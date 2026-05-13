# frozen_string_literal: true

require "set"
require "concurrent"
require "timeout"

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

      targets = scope.order(updated_at: :desc, id: :asc).limit(limit).to_a
      puts "[Pipeline] 対象レコード: #{targets.size}件 (serp_status=NULL かつ tel/url/contact_url いずれか空)"

      if targets.empty?
        return { targets: 0, extracted: 0, registered: { skipped_blank: 0 } }
      end

      # 検索キーワード生成: company + address の組み合わせ
      # query 文字列ではなく customer_id を持ち回り、同一クエリでも対象レコードを崩さない。
      query_jobs = targets.filter_map do |c|
        keyword = [c.company.to_s.strip, c.address.to_s.strip].reject(&:empty?).join(" ")
        keyword += " 会社概要" if keyword.present?
        q = keyword.presence || c.company.to_s.strip
        next if q.blank?

        { customer_id: c.id, company: c.company.to_s.strip, query: q }
      end
      queries = query_jobs.map { |job| job[:query] }

      if queries.empty?
        puts "[Pipeline] 有効なクエリが生成できませんでした。処理を中断します。"
        return { targets: targets.size, queries: 0, extracted: 0, registered: { skipped_blank: 0 } }
      end

      # Mark targets before network work so concurrent/manual runs do not pick
      # the same rows. mark_serp_status also touches updated_at for UI filters.
      mark_serp_status(targets, "serp_queued") unless dry_run

      companies = []
      batch = []
      target_ids = targets.map(&:id)
      serp_error_customer_ids = []
      completion_status_applied = false
      begin
        # SERP API 実行
        client = SerpClient.new
        batch = client.batch_search(queries, delay_between: 1)
        batch.each_with_index do |item, idx|
          job = query_jobs[idx]
          next if job.blank?

          item["customer_id"] = job[:customer_id]
          item["customer_company"] = job[:company]
        end
        ResultStore.save_batch(batch)
        serp_error_customer_ids = batch.filter_map do |item|
          next if item.dig("result", "error").blank?

          item["customer_id"]
        end.uniq
        puts "[Pipeline] SERP APIエラー: #{serp_error_customer_ids.size}件（対象はserp_errorにします）" if serp_error_customer_ids.any?

        # 抽出
        companies = batch.flat_map do |item|
          CompanyExtractor.extract(item["result"], query: item["query"]).map do |company|
            company.merge(
              customer_id: item["customer_id"],
              customer_company: item["customer_company"]
            )
          end
        end

        # Web補完: SERP で取得した URL から tel/address/contact_url を抽出して既存レコードを更新
        # 並列化方針:
        #   - SERP API 呼び出しは直列のまま（API レート制限のため変更不可）
        #   - WebEnricher の HTTP クロールは customer 単位で並列実行
        #   - 同一 customer の URL 群はスレッド内で「先頭からマッチした1件」を採用
        #     （短い社名で複数別会社にマッチして住所が連続上書きされる事故を防止）
        #   - 並列度は ENV["WEB_ENRICHER_CONCURRENCY"] (default 3) で調整可能
        unless dry_run
          counters = Hash.new(0)
          mutex    = Mutex.new
          with_url = companies.count { |c| c[:url].present? }
          concurrency = ENV.fetch("WEB_ENRICHER_CONCURRENCY", "3").to_i.clamp(1, 10)
          web_timeout = web_enricher_timeout_seconds
          web_enricher = WebEnricher
          puts "[WebEnricher] 開始: SERP抽出 #{companies.size}件 / URLあり #{with_url}件 / 並列度 #{concurrency}"

          # customer_id ごとにグループ化（nil customer は処理対象外）
          groups = companies.each_with_index.group_by { |c, _| c[:customer_id] }
          counters[:no_customer] = (groups[nil] || []).size
          (groups[nil] || []).each do |c, idx|
            puts "[WebEnricher] #{idx + 1}/#{companies.size}: customer未マッチ query='#{c[:query]}' url=#{c[:url]} → SKIP"
          end
          groups.delete(nil)

          pool = Concurrent::FixedThreadPool.new(concurrency)
          futures = groups.map do |customer_id, group|
            Concurrent::Promises.future_on(pool) do
              customer = Customer.find_by(id: customer_id)
              next if customer.nil?

              # group は [[company_hash, idx], ...] の配列。
              # SERP の上位順を保ったまま走査し、最初に updates が成立した時点で打ち切る。
              group.sort_by { |_, idx| idx }.each do |company, idx|
                direct_updates = build_serp_updates(customer, company)
                if direct_updates.any?
                  customer.update_columns(direct_updates.merge(updated_at: Time.current))
                  customer.reload
                  mutex.synchronize do
                    counters[:serp_direct] += 1
                    puts "  -> SERP直接更新: #{direct_updates.keys.join(', ')} (customer ID=#{customer.id})"
                  end
                end

                if company[:url].blank?
                  mutex.synchronize { counters[:no_url] += 1 }
                  next
                end

                if UrlPolicy.excluded_url?(company[:url], title: company[:company])
                  mutex.synchronize do
                    counters[:excluded_url] += 1
                    puts "[WebEnricher] #{idx + 1}/#{companies.size}: excluded url=#{company[:url]} title='#{company[:company]}'"
                  end
                  next
                end

                mutex.synchronize do
                  puts "[WebEnricher] #{idx + 1}/#{companies.size}: customer=#{customer.company} (ID=#{customer.id}) / candidate=#{company[:company]} (#{company[:url]})"
                end
                begin
                  web_data = Timeout.timeout(web_timeout) do
                    web_enricher.enrich_from_url(company[:url], customer)
                  end
                  updates = build_web_updates(customer, company, web_data)

                  if updates.any?
                    customer.update_columns(updates.merge(updated_at: Time.current))
                    mutex.synchronize do
                      counters[:enriched] += 1
                      puts "  -> 更新: #{updates.keys.join(', ')} (customer ID=#{customer.id})"
                    end
                    break  # この customer は決着済み。後続 URL は処理しない
                  else
                    mutex.synchronize { puts "  -> 更新なし（既存データあり or 取得不可） customer ID=#{customer.id}" }
                  end
                rescue => e
                  Rails.logger.warn("[Pipeline] WebEnricher error for #{company[:url]}: #{e.message}")
                  mutex.synchronize { puts "  -> ERROR (skipping): #{e.message}" }
                end
              end
            end
          end

          Concurrent::Promises.zip(*futures).wait
          pool.shutdown
          pool.wait_for_termination

          puts "[Pipeline] Web補完 完了: #{counters[:enriched]}件更新 / SERP直接更新 #{counters[:serp_direct]}件 / スキップ(URL無) #{counters[:no_url]}件 / スキップ(URL除外) #{counters[:excluded_url]}件 / スキップ(顧客未マッチ) #{counters[:no_customer]}件"
        end

        if detect_contact
          puts "[Pipeline] DB mode: skipped ContactUrlEnricher (WebEnricher handles persisted contact_url)"
        end
        normalized = DataNormalizer.normalize_batch(companies)
        ResultExporter.to_csv(normalized)

        # DB mode enriches existing Customer rows only. The legacy registrar is
        # intentionally skipped here because importing SERP candidates can create
        # duplicate/low-confidence Customer rows.
        reg_stats = if dry_run
          { dry_run: true }
        else
          puts "[Pipeline] DB mode: skipped CustomerRegistrar import (existing customers were enriched above)"
          { skipped_import: normalized.size, reason: "db_mode_updates_existing_customers_only" }
        end

        # 実行済みステータスに更新。SERP API自体が失敗した対象は完了扱いにしない。
        unless dry_run
          done_ids = target_ids - serp_error_customer_ids
          mark_serp_status(done_ids, "serp_done")
          mark_serp_status(serp_error_customer_ids, "serp_error")
          completion_status_applied = true
        end

        # 抽出率記録（SERP 生データの抽出率）
        label = industry.present? ? "serp_db_#{industry}_#{Time.current.strftime('%Y%m%d')}" : "serp_db_#{Time.current.strftime('%Y%m%d')}"
        ExtractionStats.record(
          companies,
          industry_label: label,
          total_queries: queries.size,
          serp_errors: batch.count { |b| b["result"]["error"] }
        )

        # WebEnricher 補完後の最終取得率（DB 実データの充足状況）
        # ExtractionStats は SERP 生配列の集計なので WebEnricher 更新分が反映されない。
        # 取引先向けに「実際に DB に入った最終状態」を別セクションで表示する。
        unless dry_run
          final = Customer.where(id: target_ids)
          n = final.count
          tel_c     = final.where.not(tel: [nil, '']).count
          addr_c    = final.where.not(address: [nil, '']).count
          url_c     = final.where.not(url: [nil, '']).count
          contact_c = final.where.not(contact_url: [nil, '']).count
          full_c    = final.where.not(tel: [nil, ''])
                           .where.not(address: [nil, ''])
                           .where.not(url: [nil, ''])
                           .where.not(contact_url: [nil, ''])
                           .count
          pct = ->(v) { n.zero? ? 0.0 : (v.to_f / n * 100).round(1) }
          puts "\n=== 最終取得率（WebEnricher補完後）==="
          puts "対象: #{n}件（今回SERPで検索した企業数）"
          puts "  tel取得:         #{tel_c}/#{n} (#{pct.call(tel_c)}%)"
          puts "  address取得:     #{addr_c}/#{n} (#{pct.call(addr_c)}%)"
          puts "  url取得:         #{url_c}/#{n} (#{pct.call(url_c)}%)"
          puts "  contact_url取得: #{contact_c}/#{n} (#{pct.call(contact_c)}%)"
          puts "  fully_enriched:  #{full_c}/#{n} (#{pct.call(full_c)}%)"
        end

        puts "[Pipeline] 完了: #{targets.size}件対象 / #{companies.size}件抽出"
        { targets: targets.size, queries: queries.size, extracted: companies.size, registered: reg_stats }
      rescue Interrupt => e
        Rails.logger.warn("[Pipeline] execute_from_db interrupted: #{e.class} #{e.message}")
        puts "[Pipeline] INTERRUPTED: #{e.message}"
        raise
      rescue => e
        # Keep failures visible and out of the automatic target scope.
        Rails.logger.error("[Pipeline] execute_from_db 例外: #{e.class} #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        puts "[Pipeline] ERROR: #{e.message}"
        raise
      ensure
        unless dry_run || completion_status_applied
          queued_ids = Customer.where(id: target_ids, serp_status: "serp_queued").pluck(:id)
          mark_serp_status(queued_ids, "serp_error")
        end
      end
    end

    def self.mark_serp_status(targets, status)
      ids = Array(targets).map { |target| target.respond_to?(:id) ? target.id : target }.compact
      return if ids.empty?

      now = Time.current
      Customer.where(id: ids).find_each do |customer|
        customer.update_columns(serp_status: status, updated_at: now)
      end
    end

    def self.web_enricher_timeout_seconds
      ENV.fetch("WEB_ENRICHER_TIMEOUT_SECONDS", "30").to_f.clamp(1.0, 120.0)
    end

    def self.build_serp_updates(customer, company)
      return {} unless %w[local knowledge_graph].include?(company[:source].to_s)
      return {} unless company_matches_customer?(customer.company, company[:company])

      updates = {}
      url_is_official = UrlPolicy.official_url?(company[:url], title: company[:company])

      updates[:url] = company[:url] if customer.url.blank? && company[:url].present? && url_is_official
      updates[:tel] = company[:tel] if customer.tel.blank? && company[:tel].present?

      address = clean_address_candidate(company[:address])
      if address.present? && better_address?(address, customer.address)
        updates[:address] = address
      end

      updates
    end

    # WebEnricher の取得結果から実際に DB に書き込む updates ハッシュを生成
    # （並列実行時もスレッドセーフ — 純粋関数）
    def self.build_web_updates(customer, company, web_data)
      updates = {}
      url_is_official = UrlPolicy.official_url?(company[:url], title: company[:company])

      updates[:url]         = company[:url]         if customer.url.blank? && company[:url].present? && web_data[:matched] == true && url_is_official
      updates[:tel]         = web_data[:tel]        if customer.tel.blank? && web_data[:tel].present?
      # address: 都道府県始まり かつ 市区町村を含む正規化住所が取得できた場合のみ採用。
      # 部分住所を完全住所に補完する用途（既存値があっても上書き）。
      address = clean_address_candidate(web_data[:address])
      if address.present? && better_address?(address, customer.address)
        updates[:address] = address
      end
      if web_data[:contact_url].present? &&
         (customer.contact_url.blank? || malformed_relative_url?(customer.contact_url))
        updates[:contact_url] = web_data[:contact_url]
      end
      updates
    end

    def self.clean_address_candidate(address)
      return nil if address.blank?
      CompanyInfoExtractor.new("").send(:clean_address, address)
    end

    def self.better_address?(candidate, current)
      return false if candidate.blank?
      return true if current.blank?

      address_score(candidate) > address_score(current)
    end

    def self.address_score(address)
      s = address.to_s.strip
      return 0 if s.blank?

      score = s.length
      score += 50 if s.match?(/(?:市|区|町|村|郡)/)
      score += 100 if s.match?(/[0-9０-９]|丁目|番地|番|号|[-－ー]/)
      score
    end

    def self.malformed_relative_url?(url)
      url.to_s.include?("/../") || url.to_s.include?("/./")
    end

    def self.company_matches_customer?(customer_name, candidate_name)
      return false if customer_name.blank? || candidate_name.blank?

      norm_customer = WebEnricher.send(:normalize_company, customer_name)
      norm_candidate = WebEnricher.send(:normalize_company, candidate_name)
      WebEnricher.send(:company_match?, norm_customer, norm_candidate)
    end
  end
end
