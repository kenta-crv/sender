# frozen_string_literal: true

require "set"
require "concurrent"
require "timeout"
require "uri"

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
    # @param customer_ids [Array<Integer>, nil] UIで選んだ今回実行分のID
    # @param progress_run_id [String, nil] UI進捗表示用のrun_id
    # @param detect_contact [Boolean]
    # @param dry_run [Boolean]
    def self.execute_from_db(industry: nil, limit: 100, customer_ids: nil, progress_run_id: nil, jid: nil, detect_contact: false, dry_run: false)
      puts "=" * 60
      puts "SERP Pipeline (DB mode) 開始: #{Time.current}"
      puts "=" * 60
      progress_tracker = progress_run_id.present? ? SerpProgressTracker.new(progress_run_id) : nil
      audit_run = progress_run_id.present? ? SerpEnrichmentRun.find_by_run_id(progress_run_id) : nil
      audit_run&.update!(jid: jid.to_s) if jid.present? && audit_run.jid.blank?
      audit_prefix = "[SERP run=#{progress_run_id.presence || '-'} jid=#{jid.presence || audit_run&.jid || '-'}]"
      log = ->(message) { puts "#{audit_prefix} #{message}" }
      log.call("[Pipeline] audit context attached") if audit_run

      # 対象レコード取得
      #   - serp_status IS NULL / '' （未実行）
      #   - かつ tel / url / contact_url のいずれかが空
      # status カラムは取引先環境で別用途に使われているため参照しない。
      incomplete_scope = Customer.where(
        "(tel IS NULL OR TRIM(tel) = '') OR " \
        "(url IS NULL OR TRIM(url) = '') OR " \
        "(contact_url IS NULL OR TRIM(contact_url) = '')"
      )

      selected_ids = Array(customer_ids).map(&:to_i).reject(&:zero?).uniq
      if selected_ids.any?
        records_by_id = Customer.where(id: selected_ids).index_by(&:id)
        targets = selected_ids.filter_map { |id| records_by_id[id] }.first(limit)
      else
        scope = incomplete_scope.where(serp_status: [nil, ''])
        scope = scope.where(industry: industry) if industry.present?

        targets = scope.order(updated_at: :desc, id: :asc).limit(limit).to_a
      end
      puts "[Pipeline] 対象レコード: #{targets.size}件 (serp_status=NULL かつ tel/url/contact_url いずれか空)"

      if targets.empty?
        audit_run&.complete!(done_count: 0, error_count: 0, summary: { targets: 0, extracted: 0 })
        return { targets: 0, extracted: 0, registered: { skipped_blank: 0 } }
      end

      puts "[Pipeline] 今回の実行対象一覧:"
      targets.each do |target|
        status_label = target.serp_status.presence || "未処理"
        puts "  対象企業: #{target.company} (ID=#{target.id}, SERPステータス=#{status_label})"
      end

      # 検索キーワード生成: company + address の組み合わせ
      # query 文字列ではなく customer_id を持ち回り、同一クエリでも対象レコードを崩さない。
      query_jobs = targets.filter_map do |c|
        company_for_query = UrlPolicy.normalize_company_name(c.company).presence || c.company.to_s.strip
        keyword = [company_for_query, search_address_for_query(c.address)].reject(&:empty?).join(" ")
        keyword += " 会社概要" if keyword.present?
        q = keyword.presence || company_for_query
        next if q.blank?

        { customer_id: c.id, company: c.company.to_s.strip, query: q }
      end
      queries = query_jobs.map { |job| job[:query] }

      if queries.empty?
        puts "[Pipeline] 有効なクエリが生成できませんでした。処理を中断します。"
        audit_run&.fail!("no valid query")
        return { targets: targets.size, queries: 0, extracted: 0, registered: { skipped_blank: 0 } }
      end
      audit_run&.mark_status!("serp", serp_total: queries.size, serp_completed: 0)
      progress_tracker&.start_processing(total: queries.size)

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
        batch = client.batch_search(queries, delay_between: 1) do |event|
          progress_tracker&.serp_progress(
            completed: event["index"].to_i + 1,
            total: event["total"].to_i
          )
          audit_run&.update_columns(
            serp_completed: event["index"].to_i + 1,
            serp_total: event["total"].to_i,
            updated_at: Time.current
          )
        end
        batch.each_with_index do |item, idx|
          job = query_jobs[idx]
          next if job.blank?

          item["customer_id"] = job[:customer_id]
          item["customer_company"] = job[:company]
        end
        ResultStore.save_batch(batch)
        fatal_error = batch.find { |item| item.dig("result", "fatal") }
        serp_error_customer_ids = if fatal_error
          target_ids
        else
          batch.filter_map do |item|
            next if item.dig("result", "error").blank?

            item["customer_id"]
          end.uniq
        end
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

          # customer_id ごとにグループ化（nil customer は処理対象外）。
          # 進捗は候補URL数ではなく、UIで選択された対象企業数を母数にする。
          groups = companies.each_with_index.group_by { |c, _| c[:customer_id] }
          counters[:no_customer] = (groups[nil] || []).size
          (groups[nil] || []).each do |c, idx|
            puts "[WebEnricher] SERP候補 #{idx + 1}/#{companies.size}: customer未マッチ query='#{c[:query]}' url=#{c[:url]} → SKIP"
          end
          groups.delete(nil)
          audit_run&.mark_status!("web", web_total: target_ids.size, web_completed: 0)
          progress_tracker&.web_started(total: target_ids.size)

          pool = Concurrent::FixedThreadPool.new(concurrency)
          audit_targets = audit_run ? audit_run.targets.index_by(&:customer_id) : {}
          futures = target_ids.map do |customer_id|
            Concurrent::Promises.future_on(pool) do
              customer = Customer.find_by(id: customer_id)
              group = groups[customer_id] || []
              audit_target = audit_targets[customer_id]
              candidate_count = group.size
              result_status = nil
              selected_url = nil
              update_keys = []
              error_message = nil
              excluded_seen = false

              begin
                next if customer.nil?

                mutex.synchronize do
                  puts "[WebEnricher] 対象企業: #{customer.company} (ID=#{customer.id}) / 候補URL #{group.size}件"
                end

                if group.empty?
                  result_status = "no_candidate"
                  mutex.synchronize do
                    counters[:no_candidate] += 1
                    puts "  -> 候補URLなし（SERP抽出結果なし） customer ID=#{customer.id}"
                  end
                  next
                end

                # group は [[company_hash, idx], ...] の配列。
                # SERP の上位順を保ったまま走査し、最初に updates が成立した時点で打ち切る。
                sorted_group = group.sort_by { |company, idx| candidate_priority(customer, company, idx) }
                sorted_group.each_with_index do |(company, idx), local_idx|
                  direct_updates = build_serp_updates(customer, company)
                  if direct_updates.any?
                    customer.update_columns(direct_updates.merge(updated_at: Time.current))
                    customer.reload
                    update_keys |= direct_updates.keys.map(&:to_s)
                    mutex.synchronize do
                      counters[:serp_direct] += 1
                      puts "  -> SERP直接更新: #{direct_updates.keys.join(', ')} (customer ID=#{customer.id})"
                    end
                  end

                  if company[:url].blank?
                    mutex.synchronize { counters[:no_url] += 1 }
                    next
                  end

                  if UrlPolicy.excluded_url?(company[:url], title: url_policy_title(company))
                    excluded_seen = true
                    mutex.synchronize do
                      counters[:excluded_url] += 1
                      puts "[WebEnricher] 候補URL #{local_idx + 1}/#{sorted_group.size} (SERP #{idx + 1}/#{companies.size}): excluded url=#{company[:url]} title='#{url_policy_title(company)}'"
                    end
                    next
                  end

                  mutex.synchronize do
                    puts "[WebEnricher] 候補URL #{local_idx + 1}/#{sorted_group.size} (SERP #{idx + 1}/#{companies.size}): candidate=#{company[:company]} url=#{company[:url]}"
                  end
                  begin
                    web_data = Timeout.timeout(web_timeout) do
                      web_enricher.enrich_from_url(company[:url], customer)
                    end
                    if web_enrichment_retry_needed?(web_data)
                      retry_web_data = Timeout.timeout(web_timeout) do
                        web_enricher.enrich_from_url(company[:url], customer)
                      end
                      web_data = retry_web_data if web_enrichment_result_better?(retry_web_data, web_data)
                    end
                    updates = build_web_updates(customer, company, web_data)

                    if updates.any?
                      customer.update_columns(updates.merge(updated_at: Time.current))
                      customer.reload
                      result_status = "updated"
                      selected_url = web_data[:source_url].presence || company[:url]
                      update_keys |= updates.keys.map(&:to_s)
                      mutex.synchronize do
                        counters[:enriched] += 1
                        puts "  -> 更新: #{updates.keys.join(', ')} (customer ID=#{customer.id})"
                      end
                      break  # この customer は決着済み。後続 URL は処理しない
                    else
                      fallback_updates = build_url_fallback_update(customer, company, web_data: web_data)
                      if fallback_updates.any?
                        customer.update_columns(fallback_updates.merge(updated_at: Time.current))
                        customer.reload
                        result_status = "url_only"
                        selected_url = company[:url]
                        update_keys |= fallback_updates.keys.map(&:to_s)
                        mutex.synchronize do
                          counters[:url_fallback] += 1
                          puts "  -> URLのみ保存: #{company[:url]} (customer ID=#{customer.id})"
                        end
                      else
                        mutex.synchronize { puts "  -> 更新なし（既存データあり or 取得不可） customer ID=#{customer.id}" }
                      end
                    end
                  rescue => e
                    Rails.logger.warn("[Pipeline] WebEnricher error for #{company[:url]}: #{e.message}")
                    error_message = e.message
                    fallback_updates = build_url_fallback_update(customer, company)
                    if fallback_updates.any?
                      customer.update_columns(fallback_updates.merge(updated_at: Time.current))
                      customer.reload
                      result_status = "url_only"
                      selected_url = company[:url]
                      update_keys |= fallback_updates.keys.map(&:to_s)
                      mutex.synchronize do
                        counters[:url_fallback] += 1
                        puts "  -> ERROR後にURLのみ保存: #{company[:url]} (customer ID=#{customer.id})"
                      end
                    else
                      result_status ||= "error"
                      mutex.synchronize { puts "  -> ERROR (skipping): #{e.message}" }
                    end
                  end
                end
              ensure
                if audit_target && customer
                  final_status = result_status ||
                                 (candidate_count.zero? ? "no_candidate" : nil) ||
                                 (error_message.present? ? "error" : nil) ||
                                 (excluded_seen ? "excluded" : "no_update")

                  audit_target.refresh_after!(
                    customer: customer.reload,
                    result_status: final_status,
                    candidate_count: candidate_count,
                    selected_url: selected_url,
                    update_keys: update_keys,
                    error_message: error_message
                  )
                end
                audit_run&.increment!(:web_completed) if audit_run
                progress_tracker&.increment_web(message: customer ? "対象完了: #{customer.company}" : "対象完了: 対象なし")
              end
            end
          end

          Concurrent::Promises.zip(*futures).wait
          pool.shutdown
          pool.wait_for_termination

          puts "[Pipeline] Web補完 完了: #{counters[:enriched]}件更新 / URLのみ保存 #{counters[:url_fallback]}件 / SERP直接更新 #{counters[:serp_direct]}件 / スキップ(URL無) #{counters[:no_url]}件 / スキップ(URL除外) #{counters[:excluded_url]}件 / スキップ(候補URLなし) #{counters[:no_candidate]}件 / スキップ(顧客未マッチ) #{counters[:no_customer]}件"
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
          refresh_audit_targets!(audit_run, target_ids)
          audit_run&.complete!(
            done_count: done_ids.size,
            error_count: serp_error_customer_ids.size,
            summary: {
              targets: targets.size,
              queries: queries.size,
              extracted: companies.size
            }
          )
          completion_status_applied = true
          progress_tracker&.finish(done_count: done_ids.size, error_count: serp_error_customer_ids.size)
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
        audit_run&.fail!(e.message)
        progress_tracker&.fail(message: e.message)
        raise
      rescue => e
        # Keep failures visible and out of the automatic target scope.
        Rails.logger.error("[Pipeline] execute_from_db 例外: #{e.class} #{e.message}\n#{e.backtrace.first(5).join("\n")}")
        puts "[Pipeline] ERROR: #{e.message}"
        audit_run&.fail!(e.message)
        progress_tracker&.fail(message: e.message)
        raise
      ensure
        unless dry_run || completion_status_applied
          queued_ids = Customer.where(id: target_ids, serp_status: "serp_queued").pluck(:id)
          mark_serp_status(queued_ids, "serp_error")
          refresh_audit_targets!(audit_run, target_ids)
        end
      end
    end

    def self.refresh_audit_targets!(audit_run, target_ids)
      return if audit_run.blank?

      ids = Array(target_ids).map(&:to_i).reject(&:zero?)
      return if ids.empty?

      customers = Customer.where(id: ids).index_by(&:id)
      audit_run.targets.where(customer_id: ids).find_each do |target|
        customer = customers[target.customer_id]
        next if customer.blank?

        target.refresh_after!(
          customer: customer,
          result_status: target.result_status.presence == "pending" ? "no_update" : target.result_status,
          candidate_count: target.candidate_count,
          selected_url: target.selected_url,
          update_keys: target.update_keys,
          error_message: target.error_message
        )
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
      url_is_official = primary_company_url?(company[:url], title: company[:company])
      address = clean_address_candidate(company[:address])
      return {} if address.present? && address_prefecture_conflict?(address, customer.address)

      updates[:url] = company[:url] if customer.url.blank? && company[:url].present? && url_is_official
      updates[:tel] = company[:tel] if customer.tel.blank? && company[:tel].present?

      if address.present? && better_address?(address, customer.address)
        updates[:address] = address
      end

      updates
    end

    # WebEnricher の取得結果から実際に DB に書き込む updates ハッシュを生成
    # （並列実行時もスレッドセーフ — 純粋関数）
    def self.build_web_updates(customer, company, web_data)
      updates = {}
      source_url = web_data[:source_url].presence || company[:url]
      url_is_official = primary_company_url?(source_url, title: url_policy_title(company))
      verified_match = web_data[:matched] == true ||
                       (web_data[:matched] != false && serp_title_matches_customer?(customer, company))
      address = clean_address_candidate(web_data[:address])

      if source_url.present? &&
         verified_match &&
         url_is_official &&
         (customer.url.blank? ||
          contact_like_url?(customer.url) ||
          UrlPolicy.excluded_url?(customer.url) ||
          better_source_url?(customer, source_url, web_data))
        updates[:url] = source_url
      end
      tel = web_data[:tel].presence
      if verified_match &&
         tel.present? &&
         (customer.tel.blank? || (same_tel_digits?(customer.tel, tel) && customer.tel != tel))
        updates[:tel] = tel
      end
      # address: 都道府県始まり かつ 市区町村を含む正規化住所が取得できた場合のみ採用。
      # 部分住所を完全住所に補完する用途（既存値があっても上書き）。
      if verified_match &&
         address.present? &&
         better_address?(address, customer.address, allow_location_conflict: true, prefer_candidate_on_tie: url_is_official)
        updates[:address] = address
      end
      contact_url = web_data[:contact_url].presence
      contact_base_url = source_url.presence || customer.url.presence || company[:url]
      contact_url = nil unless contact_url.present? &&
                               UrlPolicy.official_url?(contact_url) &&
                               same_site_url?(contact_url, contact_base_url)
      if verified_match &&
         contact_url.present? &&
         (customer.contact_url.blank? ||
          malformed_relative_url?(customer.contact_url) ||
          UrlPolicy.excluded_url?(customer.contact_url) ||
          updates[:url].present?)
        updates[:contact_url] = contact_url
      elsif verified_match &&
            customer.contact_url.present? &&
            malformed_relative_url?(customer.contact_url) &&
            customer.url.present? &&
            UrlPolicy.official_url?(customer.url)
        resolved_contact = WebEnricher.send(:resolve_contact_url, customer.contact_url, customer.url)
        if resolved_contact.present? &&
           UrlPolicy.official_url?(resolved_contact) &&
           same_site_url?(resolved_contact, customer.url)
          updates[:contact_url] = resolved_contact
        end
      elsif verified_match &&
            customer.contact_url.present? &&
            UrlPolicy.excluded_url?(customer.contact_url)
        updates[:contact_url] = nil
      end
      updates
    end

    def self.build_url_fallback_update(customer, company, web_data: nil)
      return {} unless customer.url.blank?
      url = web_data&.[](:source_url).presence || company[:url]
      return {} if url.blank?
      return {} if web_data && web_data[:matched] == false
      return {} unless primary_company_url?(url, title: url_policy_title(company))

      verified_by_web = web_data && web_data[:matched] == true
      return {} unless verified_by_web || serp_title_matches_customer?(customer, company)

      { url: url }
    end

    def self.clean_address_candidate(address)
      return nil if address.blank?
      CompanyInfoExtractor.new("").send(:clean_address, address)
    end

    def self.search_address_for_query(address)
      raw = address.to_s.strip
      return "" if raw.blank?

      pref = raw[CompanyInfoExtractor::PREF_PATTERN]
      return pref.to_s if access_address?(raw)

      cleaned = clean_address_candidate(raw)
      return cleaned if cleaned.present?

      locality = raw.scan(/[^\s　,、。〒]{1,12}(?:市|区|町|村|郡)/).first
      [pref, locality].compact.join(" ").presence || raw
    end

    def self.better_address?(candidate, current, allow_location_conflict: false, prefer_candidate_on_tie: false)
      return false if candidate.blank?
      candidate_score = address_score(candidate)
      return false if candidate_score.zero?
      return true if current.blank?
      return false if candidate.to_s.strip == current.to_s.strip
      return false if !allow_location_conflict && address_prefecture_conflict?(candidate, current)

      cleaned_current = clean_address_candidate(current)
      current_score = address_score(cleaned_current.presence || current)
      return true if cleaned_current.present? &&
                     cleaned_current != current.to_s.strip &&
                     candidate_score >= current_score
      return true if prefer_candidate_on_tie && candidate_score >= (current_score - 10)

      candidate_score > address_score(current)
    end

    def self.address_prefecture_conflict?(candidate, current)
      candidate_pref = extract_prefecture(candidate)
      current_pref = extract_prefecture(current)

      candidate_pref.present? && current_pref.present? && candidate_pref != current_pref
    end

    def self.extract_prefecture(address)
      address.to_s[CompanyInfoExtractor::PREF_PATTERN]
    end

    def self.address_score(address)
      s = address.to_s.strip
      return 0 if s.blank?
      return 0 if access_address?(s)
      return 0 if s.match?(/potentialAction|urlTemplate|@type|["{}\\]/)
      return 0 if s.match?(/有料職業紹介事業|WEB広告事業|デジタルサイネージ事業|©/)
      return 0 if s.match?(/荷物積み込み場|稼働期間|現場風景|週休|役員|取締役|代表[一-龥A-Za-z]|営業本部|店[\s　]*舗|店舗|info@/)
      return 0 if s.match?(/Google\s*Map|GOOGLE\s*Map|\bMAP\b|サイトマップ|個人情報保護|購入ページ|Go\s*to\s*top|keyboard_arrow_right|事業一覧/)
      return 0 if s.match?(/READ\s*MORE/i)
      return 0 if s.match?(/_at_|自治体|行政区/)
      return 0 if s.match?(/[【［\[]\s*(?:本社代表|代表|TEL|Tel|tel|電話)/)
      return 0 if s.match?(/[【［\[]\z/)
      return 0 if s.include?("〒")
      return 0 if s.match?(/[ 　](?:建[ 　]*築|土木|内装|配送|運送業?|軽貨物.*|物流.*)\z/)
      return 0 if s.match?(/\A#{CompanyInfoExtractor::PREF_PATTERN}\s*〒/)
      return 0 if s.scan(CompanyInfoExtractor::PREF_PATTERN).size > 1
      complete_score = complete_address_score(s)
      return complete_score if complete_score.positive?

      return 0 unless s.match?(/[0-9０-９]|丁目|番地|番|号|[-－ー]/)

      score = s.length
      score += 50 if s.match?(/(?:市|区|町|村|郡)/)
      score += 100 if s.match?(/[0-9０-９]|丁目|番地|番|号|[-－ー]/)
      score
    end

    def self.complete_address_score(address)
      s = address.to_s.strip
      return 0 if s.scan(CompanyInfoExtractor::PREF_PATTERN).size != 1
      return 0 if s.match?(/駅|徒歩|車|分|〒|Google\s*Map|GOOGLE\s*Map|\bMAP\b|サイトマップ|個人情報保護|Go\s*to\s*top|keyboard_arrow_right|READ\s*MORE|代表[一-龥A-Za-z]|店[\s　]*舗|店舗|info@|_at_|[【［\[]\s*(?:本社代表|代表|TEL|Tel|tel|電話)|[【［\[]\z/i)
      return 0 unless s.match?(/(?:市|区|町|村|郡)/)
      return 0 unless s.match?(/[0-9０-９]|丁目|番地|番|号|[-－ー]/)

      s.length + 150
    end

    def self.access_address?(address)
      s = address.to_s
      s.match?(/駅/) && s.match?(/徒歩|車|バス|分/)
    end

    def self.same_tel_digits?(current, candidate)
      current_digits = current.to_s.gsub(/\D/, "")
      candidate_digits = candidate.to_s.gsub(/\D/, "")
      current_digits.present? && current_digits == candidate_digits
    end

    def self.primary_company_url?(url, title: nil)
      UrlPolicy.official_url?(url, title: title) && !contact_like_url?(url)
    end

    def self.contact_like_url?(url)
      uri = URI.parse(url.to_s)
      text = [uri.path, uri.query].compact.join(" ")
      text.match?(/contact|inquiry|toiawase|otoiawase|(?:\A|[\/_\-.?=&])form(?:\z|[\/_\-.?=&])|mail/i)
    rescue URI::InvalidURIError
      false
    end

    def self.malformed_relative_url?(url)
      value = url.to_s.strip
      return false if value.blank?

      !value.match?(%r{\Ahttps?://}i) || value.include?("/../") || value.include?("/./")
    end

    def self.better_source_url?(customer, source_url, web_data)
      return false if customer.url.blank?
      return false if source_url.blank? || source_url == customer.url
      return false unless profile_result_has_primary_data?(web_data)

      source_root = registrable_host_root(URI.parse(source_url).host)
      current_root = registrable_host_root(URI.parse(customer.url).host)
      return false if source_root.blank? || current_root.blank? || source_root == current_root

      customer.tel.blank? || address_score(customer.address) < address_score(web_data[:address])
    rescue URI::InvalidURIError
      false
    end

    def self.profile_result_has_primary_data?(web_data)
      web_data && (web_data[:tel].present? || web_data[:address].present?)
    end

    def self.web_enrichment_retry_needed?(web_data)
      return true if web_data.blank?
      return true if web_data[:matched] == false

      web_data[:tel].blank? && web_data[:address].blank? && web_data[:contact_url].blank?
    end

    def self.web_enrichment_result_better?(candidate, current)
      return false if candidate.blank?
      return true if current.blank?
      return true if candidate[:matched] == true && current[:matched] != true
      return true if profile_result_has_primary_data?(candidate) && !profile_result_has_primary_data?(current)

      candidate[:contact_url].present? && current[:contact_url].blank?
    end

    def self.same_site_url?(url, base_url)
      uri = URI.parse(url.to_s)
      base_uri = URI.parse(base_url.to_s)
      url_root = registrable_host_root(uri.host)
      base_root = registrable_host_root(base_uri.host)
      url_root.present? && base_root.present? && url_root == base_root
    rescue URI::InvalidURIError
      false
    end

    def self.registrable_host_root(host)
      parts = host.to_s.downcase.sub(/\Awww\./, "").split(".").reject(&:blank?)
      return nil if parts.size < 2

      if parts.last == "jp" && %w[co ne or ac go ed gr lg].include?(parts[-2]) && parts.size >= 3
        parts.last(3).join(".")
      else
        parts.last(2).join(".")
      end
    end

    def self.company_matches_customer?(customer_name, candidate_name)
      return false if customer_name.blank? || candidate_name.blank?

      norm_customer = WebEnricher.send(:normalize_company, customer_name)
      norm_candidate = WebEnricher.send(:normalize_company, candidate_name)
      WebEnricher.send(:company_match?, norm_customer, norm_candidate)
    end

    def self.serp_title_matches_customer?(customer, company)
      company_matches_customer?(customer.company, company[:company]) ||
        company_matches_customer?(customer.company, company[:title])
    end

    def self.url_policy_title(company)
      company[:title].presence || company[:company]
    end

    def self.candidate_priority(customer, company, index)
      url = company[:url].to_s
      path = URI.parse(url).path.to_s.downcase rescue ""

      score = index.to_i
      score -= 100 if path.match?(%r{/(?:company|corporate|about|profile)(?:/|[-_a-z]*\.html?|$)})
      score -= 90 if path.match?(%r{/(?:kaishagaiyo|gaiyo|gaiyou)(?:/|\.html?|$)})
      score -= 80 if path.match?(%r{/(?:outline|gaiyou)(?:/|\.html?|$)})
      score += 60 if path.match?(%r{/(?:branch|office|network|list|jigyosyoannai)(?:/|\.|$)})

      if customer&.company.to_s.match?(/センター|支店|営業所|出張所|オフィス|事業所|本店|本社|支社|工場|店/)
        score -= 70 if path.match?(%r{/(?:branch|office|network|list|introduction|jigyosyoannai)(?:/|\.|$)})
      end
      if customer&.company.to_s.match?(/センター|ステーション|支店|営業所|出張所|オフィス|事業所|本店|本社|支社|工場|店|施設|ホーム|多居夢/)
        score -= 95 if path.match?(%r{/(?:facility|shop|branch|office|store)(?:/|\.|$)})
      end

      [score, index.to_i]
    end
  end
end
