# frozen_string_literal: true

module BrightData
  class Pipeline
    def self.execute(csv_path:, keyword_column: "company", delay_between: 1,
                     detect_contact: false, dry_run: false)
      puts "=" * 60
      puts "SERP Pipeline 開始: #{Time.current}"
      puts "=" * 60

      # 1. CSV読込
      keywords = CsvLoader.load(csv_path, keyword_column: keyword_column)

      # 2. SERP API
      client = SerpClient.new
      batch = client.batch_search(keywords, delay_between: delay_between)
      ResultStore.save_batch(batch)

      # 3. 抽出
      companies = CompanyExtractor.extract_batch(batch)

      # 4. 問い合わせURL（オプション）
      companies = ContactUrlEnricher.enrich(companies) if detect_contact

      # 5. 正規表現整形
      normalized = DataNormalizer.normalize_batch(companies)

      # 6. CSV出力
      ResultExporter.to_csv(normalized)

      # 7. DB登録
      reg_stats = dry_run ? { dry_run: true } : CustomerRegistrar.register(normalized)

      # 8. 抽出率記録
      ExtractionStats.record(
        companies,
        industry_label: "batch_#{Time.current.strftime('%Y%m%d')}",
        total_queries: keywords.size,
        serp_errors: batch.count { |b| b["result"]["error"] }
      )

      { keywords: keywords.size, extracted: companies.size, registered: reg_stats }
    end

    # UI経由でDB上の不完全顧客データを対象にSERP検索を実行する
    # 対象条件（KEN指定）:
    #   - company に敬称（株式会社等）を含まない
    #   - tel が空
    #   - address に都道府県が含まれない
    #   - url が空
    # いずれかに該当し、かつ serp_queued / serp_done でないレコードを対象とする
    #
    # @param industry [String] 業種でフィルタ（nil の場合は全件）
    # @param limit [Integer] 処理件数上限
    # @param detect_contact [Boolean]
    # @param dry_run [Boolean]
    def self.execute_from_db(industry: nil, limit: 100, detect_contact: false, dry_run: false)
      puts "=" * 60
      puts "SERP Pipeline (DB mode) 開始: #{Time.current}"
      puts "=" * 60

      # 対象レコード取得（実行済みを除外）
      scope = Customer.where(serp_status: nil).or(Customer.where.not(serp_status: %w[serp_queued serp_done]))

      # 業種フィルタ
      scope = scope.where(industry: industry) if industry.present?

      targets = scope.limit(limit).to_a

      # 不完全データ条件（SQLite REGEXP非対応のためRubyで判定）
      corp_pattern = /株式会社|有限会社|合同会社|一般社団法人|一般財団法人|社会福祉法人|医療法人|学校法人/
      pref_pattern = /東京都|大阪府|北海道|神奈川県|愛知県|福岡県|埼玉県|千葉県|兵庫県|静岡県|茨城県|広島県|京都府|宮城県|新潟県|長野県|岐阜県|群馬県|栃木県|岡山県|福島県|三重県|熊本県|鹿児島県|沖縄県|滋賀県|山口県|愛媛県|長崎県|奈良県|青森県|岩手県|大分県|石川県|山形県|宮崎県|富山県|秋田県|香川県|和歌山県|佐賀県|福井県|徳島県|高知県|島根県|鳥取県|山梨県/
      targets = targets.select do |c|
        !c.company.to_s.match?(corp_pattern) || c.tel.blank? ||
        c.address.blank? || !c.address.to_s.match?(pref_pattern) ||
        c.url.blank?
      end
      puts "[Pipeline] 対象レコード: #{targets.size}件"

      if targets.empty?
        return { targets: 0, extracted: 0, registered: { skipped_blank: 0 } }
      end

      # 検索キーワード生成: company + address の組み合わせ
      queries = targets.map do |c|
        keyword = [c.company.to_s.strip, c.address.to_s.strip].reject(&:empty?).join(" ")
        keyword += " 会社概要" if keyword.present?
        keyword.presence || c.company.to_s.strip
      end.compact.uniq

      if queries.empty?
        puts "[Pipeline] 有効なクエリが生成できませんでした。処理を中断します。"
        return { targets: targets.size, queries: 0, extracted: 0, registered: { skipped_blank: 0 } }
      end

      # 対象レコードをserp_queued にマーク（ループ防止）
      # ensure で例外時も serp_done にフォールバックするため先にマーク
      unless dry_run
        Customer.where(id: targets.map(&:id)).update_all(serp_status: "serp_queued")
      end

      companies = []
      batch = []
      begin
        # SERP API 実行
        client = SerpClient.new
        batch = client.batch_search(queries, delay_between: 1)
        ResultStore.save_batch(batch)

        # 抽出
        companies = CompanyExtractor.extract_batch(batch)
        companies = ContactUrlEnricher.enrich(companies) if detect_contact
        normalized = DataNormalizer.normalize_batch(companies)
        ResultExporter.to_csv(normalized)

        # DB登録
        reg_stats = dry_run ? { dry_run: true } : CustomerRegistrar.register(normalized)

        # 実行済みステータスに更新
        unless dry_run
          Customer.where(id: targets.map(&:id)).update_all(serp_status: "serp_done")
        end

        # 抽出率記録
        label = industry.present? ? "serp_db_#{industry}_#{Time.current.strftime('%Y%m%d')}" : "serp_db_#{Time.current.strftime('%Y%m%d')}"
        ExtractionStats.record(
          companies,
          industry_label: label,
          total_queries: queries.size,
          serp_errors: batch.count { |b| b["result"]["error"] }
        )

        puts "[Pipeline] 完了: #{targets.size}件対象 / #{companies.size}件抽出"
        { targets: targets.size, queries: queries.size, extracted: companies.size, registered: reg_stats }
      rescue => e
        # 例外発生時: serp_queued のままにせず serp_error にして再実行可能にする
        unless dry_run
          Customer.where(id: targets.map(&:id)).update_all(serp_status: nil)
        end
        Rails.logger.error("[Pipeline] execute_from_db 例外: #{e.class} #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        puts "[Pipeline] ERROR: #{e.message}"
        raise
      end
    end
  end
end
