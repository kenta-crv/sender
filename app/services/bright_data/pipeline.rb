# frozen_string_literal: true

require "set"

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
    # 対象条件（取引先運用で status カラムは別用途のため serp_status ベースで判定）:
    #   - serp_status が NULL（未実行）
    #   - かつ tel / url / contact_url のいずれかが空
    # status カラムの値は問わない。
    #
    # @param industry [String] 業種でフィルタ（nil の場合は全件）
    # @param limit [Integer] 処理件数上限
    # @param detect_contact [Boolean]
    # @param dry_run [Boolean]
    def self.execute_from_db(industry: nil, limit: 100, detect_contact: false, dry_run: false)
      puts "=" * 60
      puts "SERP Pipeline (DB mode) 開始: #{Time.current}"
      puts "=" * 60

      # 対象レコード取得
      #   - serp_status IS NULL / '' （未実行）
      #   - かつ tel / url / contact_url のいずれかが空
      # status カラムは取引先環境で別用途に使われているため参照しない。
      scope = Customer.where(serp_status: [nil, ''])
                      .where(
                        "(tel IS NULL OR TRIM(tel) = '') OR " \
                        "(url IS NULL OR TRIM(url) = '') OR " \
                        "(contact_url IS NULL OR TRIM(contact_url) = '')"
                      )

      # 業種フィルタ
      scope = scope.where(industry: industry) if industry.present?

      targets = scope.limit(limit).to_a
      puts "[Pipeline] 対象レコード: #{targets.size}件 (serp_status=NULL かつ tel/url/contact_url いずれか空)"

      if targets.empty?
        return { targets: 0, extracted: 0, registered: { skipped_blank: 0 } }
      end

      # 検索キーワード生成: company + address の組み合わせ
      # query → customer の逆引きマップも同時に構築
      query_customer_map = {}
      queries = targets.map do |c|
        keyword = [c.company.to_s.strip, c.address.to_s.strip].reject(&:empty?).join(" ")
        keyword += " 会社概要" if keyword.present?
        q = keyword.presence || c.company.to_s.strip
        query_customer_map[q] = c if q.present?
        q
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

        # Web補完: SERP で取得した URL から tel/address/contact_url を抽出して既存レコードを更新
        unless dry_run
          web_enrich_count = 0
          skipped_no_url = 0
          skipped_no_customer = 0
          skipped_already_updated = 0
          # 同一 customer に対しては「最初にマッチした公式サイト」1社のみで更新する。
          # 短い社名（例: 「東和」）が複数の別会社にマッチし、住所等が
          # 繰り返し上書きされるのを防ぐための安全策。
          updated_customer_ids = Set.new
          with_url = companies.count { |c| c[:url].present? }
          puts "[WebEnricher] 開始: SERP抽出 #{companies.size}件 / URLあり #{with_url}件"
          companies.each_with_index do |company, idx|
            if company[:url].blank?
              skipped_no_url += 1
              next
            end
            customer = query_customer_map[company[:query]]
            if customer.nil?
              skipped_no_customer += 1
              puts "[WebEnricher] #{idx + 1}/#{companies.size}: customer未マッチ query='#{company[:query]}' url=#{company[:url]} → SKIP"
              next
            end
            if updated_customer_ids.include?(customer.id)
              skipped_already_updated += 1
              puts "[WebEnricher] #{idx + 1}/#{companies.size}: customer ID=#{customer.id} は既に更新済み → SKIP"
              next
            end

            puts "[WebEnricher] #{idx + 1}/#{companies.size}: #{company[:company]} (#{company[:url]})"
            begin
              web_data = WebEnricher.enrich_from_url(company[:url], customer)

              updates = {}
              # URL: 会社名マッチが確認できた場合のみ SERP URL を採用
              # matched=true(確認済み) or matched=nil かつ有益なデータが得られた場合
              # ディレクトリサイトは url として保存しない
              url_reliable = web_data[:matched] == true ||
                             (web_data[:matched].nil? && (web_data[:tel].present? || web_data[:contact_url].present? || web_data[:address].present?))
              url_is_directory = WebEnricher.directory_url?(company[:url])
              updates[:url]         = company[:url]           if customer.url.blank?         && company[:url].present? && url_reliable && !url_is_directory
              updates[:tel]         = web_data[:tel]           if customer.tel.blank?         && web_data[:tel].present?
              # address: 都道府県始まりの正規化住所が取得できた場合は既存値を上書き（部分住所を完全住所に補完）
              #          都道府県始まりでない場合は誤データ防止のため既存値を維持
              if web_data[:address].present? && web_data[:address].match?(CompanyInfoExtractor::PREF_PATTERN)
                updates[:address] = web_data[:address]
                if customer.address.present? && customer.address != web_data[:address]
                  puts "  [WebEnricher] address上書き: '#{customer.address}' → '#{web_data[:address]}'"
                end
              end
              updates[:contact_url] = web_data[:contact_url]   if customer.contact_url.blank? && web_data[:contact_url].present?

              if updates.any?
                # update_columns でバリデーション・コールバックをスキップ。
                # 取引先環境で Customer に belongs_to :client 等が追加されている場合でも
                # "Client must exist" などで失敗しないようにする。
                # updated_at は手動で付与（update_columns は自動更新しないため）。
                customer.update_columns(updates.merge(updated_at: Time.current))
                updated_customer_ids << customer.id
                web_enrich_count += 1
                puts "  -> 更新: #{updates.keys.join(', ')}"
              else
                puts "  -> 更新なし（既存データあり or 取得不可）"
              end
            rescue => e
              Rails.logger.warn("[Pipeline] WebEnricher error for #{company[:url]}: #{e.message}")
              puts "  -> ERROR (skipping): #{e.message}"
            end

            sleep(0.5)
          end
          puts "[Pipeline] Web補完 完了: #{web_enrich_count}件更新 / スキップ(URL無) #{skipped_no_url}件 / スキップ(顧客未マッチ) #{skipped_no_customer}件 / スキップ(更新済) #{skipped_already_updated}件"
        end

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
