# frozen_string_literal: true

require "timeout"
require "uri"

module BrightData
  # SERPで取得した企業URLから会社情報を補完するサービス
  #
  # 処理フロー:
  #   1. トップページを HTTP GET (CompanyInfoExtractor.fetch_and_parse)
  #   2. 会社名マッチング検証（誤マッチ防止）
  #   3. 「会社概要」等のプロフィールページリンクを探してリダイレクト
  #   4. プロフィールページを再取得して tel / address / company / contact_url を抽出
  #
  # 戻り値の :matched キー:
  #   true  … 会社名が一致確認済み
  #   false … 不一致（呼び出し側でスキップ）
  #   nil   … 検証不能（ページから会社名を取得できず）
  class WebEnricher
    PROFILE_LINK_TEXT = /会社概要|企業概要|企業情報|会社案内|会社情報|会社紹介|コーポレート|about\s*us|about\s*company/i

    PROFILE_LINK_PATH = /\/company(?:-info|-profile|-about)?(?:\/|\.html?)?$|
                          \/company\/(?:outline|profile|about|gaiyou|info|index)(?:\/|\.html?)?$|
                          \/kaisyaannai\/(?:kaishagaiyo|gaiyo|company|profile)?(?:\/|\.html?)?$|
                          \/about(?:-us)?(?:\/|\.html?)?$|
                          \/profile(?:\/|\.html?)?$|
                          \/corp(?:orate)?(?:\/|\.html?)?$|
                          \/corporate\/(?:overview|outline|profile|about|company)(?:\/|\.html?)?$|
                          \/kaisha(?:gaiyou)?(?:\/|\.html?)?$|
                          \/kigyou(?:jouhou)?(?:\/|\.html?)?$/xi

    PROFILE_CANDIDATE_PATHS = [
      "/corporate/overview",
      "/corporate/outline",
      "/corporate/profile",
      "/kaisyaannai/kaishagaiyo/",
      "/kaisyaannai/",
      "/company/outline/",
      "/company/outline",
      "/company/overview/",
      "/company/overview",
      "/company/profile/",
      "/company/profile",
      "/company/profile.html",
      "/company/index.html",
      "/company.html",
      "/company/info/",
      "/company/info.html",
      "/company/about/",
      "/company/gaiyou.html",
      "/COMPANY/gaiyou.html",
      "/about/company/",
      "/about/company.html",
      "/about/profile/",
      "/about/profile.html",
      "/about/index.html",
      "/gaiyo/",
      "/gaiyou/",
      "/outline/",
      "/overview/",
      "/introduction/",
      "/about/",
      "/profile/",
      "/profile.html",
      "/info/",
      "/company/",
      "/company"
    ].freeze
    FETCH_TIMEOUT_SECONDS = ENV.fetch("WEB_ENRICHER_FETCH_TIMEOUT_SECONDS", "8").to_f.clamp(2.0, 30.0)
    RENDER_TIMEOUT_SECONDS = ENV.fetch("WEB_ENRICHER_RENDER_TIMEOUT_SECONDS", "10").to_f.clamp(4.0, 30.0)
    MAX_PROFILE_CANDIDATES = ENV.fetch("WEB_ENRICHER_PROFILE_CANDIDATES", "8").to_i.clamp(1, 20)
    MAX_RENDERED_PROFILE_CANDIDATES = 1

    # ── 正規化用パターン ──

    # 法人格（前置・後置とも）
    CORP_REGEX = /株式会社|\(株\)|（株）|有限会社|\(有\)|（有）|合同会社|合資会社|
                  一般社団法人|一般財団法人|社会福祉法人|医療法人|学校法人|
                  特定非営利活動法人|NPO法人|
                  co\.,?\s*ltd\.?|inc\.?|corp\.?|llc\.?/ix

    # 敬称・肩書き
    HONORIFIC_REGEX = /御中|様\z/

    # 支店・営業所等（末尾に出現するもの）
    LEADING_JOB_TITLE_REGEX = /\A(?:業務委託|正社員|契約社員|派遣社員|アルバイト|パート)\s+/
    BRANCH_REGEX = /(?:\S{1,10}(?:支店|営業所|出張所|オフィス|事業所|本店|本社|支社|事務所|店))\z/
    BRANCH_DEPARTMENT_SUFFIX_REGEX = %r{[\/／]\s*[^\/／]*(?:支店|営業所|出張所|オフィス|事業所|本店|本社|支社|事務所)?[^\/／]*(?:宅配課|配送課|配達課|営業課|総務課|事務課|管理課|採用課|人事課|物流課|運送課|営業部|総務部|人事部|管理部|物流部|運送部|センター).*\z}
    DEPARTMENT_REGEX = /(?:宅配課|配送課|配達課|営業課|総務課|事務課|管理課|採用課|人事課|物流課|運送課|\S{1,12}(?:営業部|総務部|人事部|管理部|物流部|運送部))\z/
    BUSINESS_SUFFIX_REGEX = /(?:倉庫|運送|配送|作業|ドライバー)\z/

    # @param url [String]
    # @param customer [Customer|OpenStruct|nil]
    # @return [Hash]  :matched => true|false|nil, その他 :tel/:address/:contact_url/:company
    def self.enrich_from_url(url, customer = nil)
      # 1. トップページを取得
      top_extractor = fetch_extractor(url, customer)
      if top_extractor.nil?
        Rails.logger.warn("[WebEnricher] トップページ取得失敗: #{url}")
        return { matched: false }
      end

      # 2. 会社名マッチング検証
      matched_flag = nil
      if customer&.company.present?
        norm_customer = normalize_company(customer.company)
        norm_customer_candidates = normalized_customer_candidates(customer.company)

        # まず法人格付き会社名をページから抽出して比較
        page_company = extract_page_company(top_extractor.doc)
        if page_company.present?
          norm_page = normalize_company(page_company)
          matched_flag = norm_customer_candidates.any? { |candidate| company_match?(candidate, norm_page) }

          if matched_flag
            puts "  [WebEnricher] match check: '#{norm_customer}' ⊆ '#{norm_page}' → MATCH"
          else
            prominent_name_found = norm_customer_candidates.any? do |candidate|
              customer_name_in_page?(top_extractor.doc, candidate)
            end

            if prominent_name_found
              matched_flag = true
              puts "  [WebEnricher] page company mismatch but customer name found: '#{norm_customer}' vs '#{norm_page}' → MATCH"
            elsif confident_page_company_mismatch?(norm_page)
              puts "  [WebEnricher] mismatch: '#{norm_customer}' vs '#{norm_page}' → SKIP"
              return { matched: false }
            else
              name_found = customer_name_present_in_doc?(top_extractor.doc, norm_customer_candidates)
              if name_found
                matched_flag = true
                puts "  [WebEnricher] page company mismatch but customer name found: '#{norm_customer}' vs '#{norm_page}' → MATCH"
              else
                puts "  [WebEnricher] mismatch: '#{norm_customer}' vs '#{norm_page}' → SKIP"
                return { matched: false }
              end
            end
          end
        else
          # ページから法人名を抽出できなかった場合: title/h1 で確認
          name_found = customer_name_present_in_doc?(top_extractor.doc, norm_customer_candidates)
          if name_found == false
            puts "  [WebEnricher] mismatch: '#{norm_customer}' not found in page → SKIP"
            return { matched: false }
          elsif name_found
            matched_flag = true
            puts "  [WebEnricher] company not detected on page, name found in text"
          else
            matched_flag = nil
            puts "  [WebEnricher] company not detected on page, proceeding"
          end
        end
      end

      # SERPが会社概要ページを直接返す場合がある。
      # そのページでtel/addressが取れているなら、別の概要リンクへ移動せず採用する。
      top_result = top_extractor.extract
      branch_specific = branch_tokens(customer&.company).any?
      if top_result[:tel].present? &&
         top_result[:address].present? &&
         branch_match_safe?(top_extractor.doc, customer, address: top_result[:address]) &&
         (!profile_listing_url?(url) || branch_specific)
        result = top_result.merge(matched: matched_flag, source_url: url)
        if result[:contact_url].present?
          result[:contact_url] = resolve_contact_url(result[:contact_url], url)
        end
        return result
      end

      # 3. 会社概要ページのリンクを探す
      profile_url = find_profile_link(top_extractor.doc, url)
      puts "  [WebEnricher] profile_url: #{profile_url || '(not found, using top page)'}"

      # 4. 会社概要ページを取得
      target_url = profile_url.presence || url
      target_extractor = if profile_url.present? && profile_url != url
        fetch_extractor(profile_url, customer) || top_extractor
      else
        top_extractor
      end

      # 5. 情報を抽出して :matched を付加して返す
      result = sanitized_result(target_extractor, matched_flag, customer)
      if profile_result_has_primary_data?(top_result) &&
         branch_match_safe?(top_extractor.doc, customer, address: top_result[:address])
        result = merge_profile_results(top_result.merge(matched: matched_flag), result)
      end

      if profile_result_needs_primary_completion?(result)
        rendered_extractor = fetch_rendered_extractor(target_url, customer)
        if rendered_extractor
          rendered_result = sanitized_result(rendered_extractor, matched_flag, customer)
          if profile_result_improves_primary_data?(rendered_result, result)
            target_extractor = rendered_extractor
            result = merge_profile_results(result, rendered_result)
          end
        end
      end

      if profile_result_needs_primary_completion?(result)
        candidate = fetch_candidate_profile(url, customer, matched_flag, result)
        if candidate
          target_url, target_extractor, candidate_result = candidate
          result = merge_profile_results(result, candidate_result)
        end
      end

      # contact_url を絶対URLに変換
      if result[:contact_url].present?
        result[:contact_url] = resolve_contact_url(result[:contact_url], target_url)
      end

      result[:source_url] = target_url
      result
    rescue => e
      Rails.logger.warn("[WebEnricher] enrich_from_url error for #{url}: #{e.message}")
      { matched: false }
    end

    private

    # ── 会社名の正規化 ──
    # 法人格・敬称・支店情報・記号・スペースを除去し、小文字化して返す
    def self.normalize_company(name)
      s = name.to_s.dup

      # 全角英数 → 半角
      s = s.tr("Ａ-Ｚａ-ｚ０-９", "A-Za-z0-9")

      # 求人タイトル由来の雇用形態・部署名を除去
      s.gsub!(LEADING_JOB_TITLE_REGEX, "")
      s.gsub!(BRANCH_DEPARTMENT_SUFFIX_REGEX, "")
      # 法人格を除去
      s.gsub!(CORP_REGEX, "")
      # 敬称を除去
      s.gsub!(HONORIFIC_REGEX, "")
      # 支店・営業所等を除去（末尾）
      s.gsub!(BRANCH_REGEX, "")
      s.gsub!(DEPARTMENT_REGEX, "")
      # 記号・スペースを除去
      s.gsub!(/[\s　・\-－ー＝=\.,、。()（）\[\]「」【】\|\/'’‘]/, "")

      s.downcase.strip
    end

    # ── マッチ判定 ──
    # 正規化済みの2つの名前で双方向 containment を判定する。
    # 短い方が3文字以上であれば、一方が他方に含まれていれば OK。
    # 3文字未満の場合は完全一致のみ。
    def self.company_match?(norm_a, norm_b)
      return false if norm_a.empty? || norm_b.empty?
      return true  if norm_a == norm_b

      shorter, longer = [norm_a, norm_b].sort_by(&:length)

      return true if shorter.length >= 3 && longer.start_with?(shorter)
      return true if shorter.length >= 4 && longer.include?(shorter)

      false  # 短い一般語の部分一致は誤マッチしやすいため採用しない
    end

    def self.normalized_customer_candidates(name)
      primary = normalize_company(name)
      candidates = [primary]
      candidates.concat(ascii_name_variants(primary))
      suffix_removed = primary.sub(BUSINESS_SUFFIX_REGEX, "")
      candidates << suffix_removed if suffix_removed.length >= 3
      candidates.concat(ascii_name_variants(suffix_removed))
      name.to_s.split(/[\s　／\/・,、()（）\[\]「」【】]+/).each do |part|
        normalized_part = normalize_company(part)
        next if generic_customer_name_part?(normalized_part)

        candidates << normalized_part if normalized_part.length >= 3
        candidates.concat(ascii_name_variants(normalized_part))
      end
      candidates.uniq.reject(&:blank?)
    end

    def self.ascii_name_variants(name)
      value = name.to_s
      return [] unless value.match?(/\A[a-z0-9]+\z/i)

      variants = []
      variants << value.sub(/e\z/i, "") if value.length >= 5 && value.match?(/e\z/i)
      variants.uniq.select { |variant| variant.length >= 3 && variant != value }
    end

    def self.generic_customer_name_part?(name)
      name.blank? ||
        name.match?(/\A(?:ドライバ|ドライバー|配送|配達|宅配|軽貨物|求人|採用|募集|スタッフ|アルバイト|パート|正社員|コネクト|connect|logistics|transport|service|support|group|company|corp|inc|co|ltd)\z/)
    end

    # ── ページの運営企業名を抽出する ──
    def self.extract_page_company(doc)
      candidates = []

      candidates << extract_corp_name(doc.at("title")&.text.to_s.strip)

      doc.css("h1").first(3).each { |h| candidates << extract_corp_name(h.text.strip) }

      if (footer = doc.at("footer"))
        ft = footer.text.gsub(/\s+/, " ").strip
        m = ft.match(/(?:©|copyright)[^\n]{0,15}?((?:株式会社|有限会社|合同会社)\s*\S+)/i)
        candidates << m[1].strip if m
        candidates << extract_corp_name(ft)
      end

      if (header = doc.at("header"))
        candidates << extract_corp_name(header.text.strip)
      end

      meta = doc.at("meta[name='description']")&.[]("content").to_s.strip
      candidates << extract_corp_name(meta) if meta.present?

      candidates.compact.reject(&:empty?).first
    end

    # テキストから最初の法人格付き会社名を抽出する
    def self.extract_corp_name(text)
      return nil if text.blank?

      m = text.match(/(?:株式会社|有限会社|合同会社|一般社団法人|一般財団法人)\s*\S+/)
      return m[0].gsub(/[[:space:]]/, "") if m

      m2 = text.match(/\S+(?:株式会社|有限会社|合同会社)/)
      return m2[0].strip if m2

      m3 = text.match(/[A-Z][A-Za-z0-9\s&'\-]{1,25}(?:,?\s*(?:Inc|Corp|LLC|Co|Ltd)\.?)+/i)
      m3 ? m3[0].strip : nil
    end

    def self.confident_page_company_mismatch?(norm_page)
      return false if norm_page.blank?
      return false if norm_page.length < 3
      return false if norm_page.match?(/\A(?:会社概要|企業情報|会社案内|概要|overview|aboutus|代表取締役|トップ|ホーム|採用|お問い合わせ)\z/i)

      true
    end

    # 顧客の正規化名がページの title/h1/h2 に含まれるか確認
    def self.customer_name_in_page?(doc, norm_customer)
      return nil if norm_customer.length < 3

      sources = [
        doc.at("title")&.text.to_s,
        *doc.css("h1").map(&:text),
        *doc.css("h2").first(2).map(&:text),
      ]

      sources.each do |src|
        norm_src = normalize_company(src)
        return true if company_match?(norm_customer, norm_src)
      end

      false
    end

    def self.customer_name_present_in_doc?(doc, norm_customer)
      candidates = Array(norm_customer).reject { |candidate| candidate.blank? || candidate.length < 3 }
      return nil if candidates.empty?
      return true if candidates.any? { |candidate| customer_name_in_page?(doc, candidate) }

      text = doc.text.to_s.gsub(/\s+/, " ")[0, 5000]
      normalized_text = normalize_company(text)
      candidates.any? { |candidate| company_match?(candidate, normalized_text) }
    end

    # ── URL ユーティリティ ──

    def self.find_profile_link(doc, base_url)
      base_uri = URI.parse(base_url) rescue nil
      return nil if base_uri.nil?
      base_host = base_uri.host.to_s.sub(/\Awww\./, "")

      doc.css("a[href]").each do |a|
        href = a["href"].to_s.strip
        text = a.text.strip

        next if href.blank?
        next if href.start_with?("javascript:", "mailto:", "tel:", "#")
        next if text.match?(/採用|求人|recruit|login|logout|ブログ|blog|news|ニュース|販売会社|グループ会社|関連会社/i)

        if text.match?(PROFILE_LINK_TEXT) || href.match?(PROFILE_LINK_PATH)
          resolved = resolve_url(href, base_uri)
          next if resolved.nil?
          next if UrlPolicy.excluded_url?(resolved, title: text)

          target_uri = URI.parse(resolved) rescue nil
          next if target_uri.nil?
          target_host = target_uri.host.to_s.sub(/\Awww\./, "")
          next unless target_host == base_host
          return resolved
        end
      end
      nil
    end

    def self.fetch_candidate_profile(base_url, customer, matched_flag, current_result = {})
      rendered_attempts = 0

      candidate_profile_urls(base_url).first(MAX_PROFILE_CANDIDATES).each do |candidate_url|
        extractor = fetch_extractor(candidate_url, customer)
        next if extractor.nil?

        result = sanitized_result(extractor, matched_flag, customer)
        return [candidate_url, extractor, result] if profile_result_improves_primary_data?(result, current_result)

        next unless rendered_attempts < MAX_RENDERED_PROFILE_CANDIDATES
        next unless customer_profile_candidate?(extractor.doc, customer)

        rendered_attempts += 1
        rendered_extractor = fetch_rendered_extractor(candidate_url, customer)
        next if rendered_extractor.nil?

        rendered_result = sanitized_result(rendered_extractor, matched_flag, customer)
        return [candidate_url, rendered_extractor, rendered_result] if profile_result_improves_primary_data?(rendered_result, current_result)
      end

      nil
    end

    def self.fetch_extractor(url, customer)
      Timeout.timeout(FETCH_TIMEOUT_SECONDS) do
        CompanyInfoExtractor.fetch_and_parse(url, customer: customer)
      end
    rescue Timeout::Error
      Rails.logger.warn("[WebEnricher] fetch timeout for #{url}")
      nil
    end

    def self.fetch_rendered_extractor(url, customer)
      Timeout.timeout(RENDER_TIMEOUT_SECONDS + 2) do
        CompanyInfoExtractor.fetch_and_parse_rendered(url, customer: customer)
      end
    rescue Timeout::Error
      Rails.logger.warn("[WebEnricher] rendered fetch timeout for #{url}")
      nil
    end

    def self.candidate_profile_urls(base_url)
      base_uri = URI.parse(base_url) rescue nil
      return [] if base_uri.nil?

      PROFILE_CANDIDATE_PATHS.filter_map do |path|
        URI.join(base_uri.to_s, path).to_s
      rescue URI::InvalidURIError
        nil
      end.uniq.reject { |candidate| candidate == base_url }
    end

    def self.customer_profile_candidate?(doc, customer)
      return true if customer&.company.blank?

      norm_customer = normalize_company(customer.company)
      page_company = extract_page_company(doc)
      return true if page_company.present? && company_match?(norm_customer, normalize_company(page_company))

      customer_name_present_in_doc?(doc, norm_customer) != false
    end

    def self.sanitized_result(extractor, matched_flag, customer)
      result = extractor.extract.merge(matched: matched_flag)
      unless branch_match_safe?(extractor.doc, customer, address: result[:address])
        result[:tel] = nil
        result[:address] = nil
      end
      result
    end

    def self.profile_result_has_data?(result)
      result[:tel].present? || result[:address].present? || result[:contact_url].present?
    end

    def self.profile_result_has_primary_data?(result)
      result[:tel].present? || result[:address].present?
    end

    def self.profile_result_needs_primary_completion?(result)
      result[:tel].blank? || result[:address].blank?
    end

    def self.profile_result_improves_primary_data?(candidate, current)
      return false unless profile_result_has_primary_data?(candidate)
      return true if current.blank? || !profile_result_has_primary_data?(current)
      return true if current[:tel].blank? && candidate[:tel].present?
      return true if current[:address].blank? && candidate[:address].present?

      candidate_address = candidate[:address].to_s
      current_address = current[:address].to_s
      candidate_address.present? && candidate_address.length > current_address.length + 5
    end

    def self.merge_profile_results(base, preferred)
      base.merge(preferred) do |key, old_value, new_value|
        if key == :matched
          new_value
        elsif %i[address contact_url].include?(key) && old_value.present?
          old_value
        else
          new_value.presence || old_value
        end
      end
    end

    # ディレクトリサイトかどうか判定
    def self.directory_url?(url)
      UrlPolicy.excluded_url?(url)
    end

    # contact_url を絶対URLに変換する
    def self.resolve_contact_url(contact_url, base_url)
      contact_url = contact_url.to_s.strip
      return nil if contact_url.blank?
      return nil if contact_url.start_with?("javascript:", "mailto:", "tel:", "#")

      base_uri = URI.parse(base_url) rescue nil
      return contact_url if base_uri.nil?

      resolved = resolve_url(contact_url, base_uri) || contact_url
      useful_contact_url?(resolved, base_url) ? resolved : nil
    rescue URI::InvalidURIError
      contact_url
    end

    def self.useful_contact_url?(contact_url, base_url)
      contact_uri = URI.parse(contact_url)
      base_uri = URI.parse(base_url)
      return true if contact_uri.host.to_s.sub(/\Awww\./, "") != base_uri.host.to_s.sub(/\Awww\./, "")

      contact_path = contact_uri.path.to_s.chomp("/")
      base_path = base_uri.path.to_s.chomp("/")
      rootish = contact_path.blank?
      same_page = contact_path == base_path

      return false if contact_uri.fragment.blank? && contact_uri.query.blank? && (rootish || same_page)

      true
    rescue URI::InvalidURIError
      true
    end

    def self.resolve_url(href, base_uri)
      href = href.to_s.strip
      return nil if href.blank?
      return nil if href.start_with?("javascript:", "mailto:", "tel:")

      URI.join(base_uri.to_s, href).to_s
    rescue URI::InvalidURIError
      nil
    end

    def self.profile_listing_url?(url)
      path = URI.parse(url).path.to_s.downcase
      path.match?(%r{/(?:branch|office|network|list|introduction)(?:/|\.|$)})
    rescue URI::InvalidURIError
      false
    end

    def self.branch_match_safe?(doc, customer, address: nil)
      company_tokens = branch_tokens(customer&.company)
      return true if company_tokens.empty?

      locality_tokens = address_locality_tokens(customer&.address)
      if address.present? && locality_tokens.any?
        normalized_address = address.to_s.gsub(/\s+/, "")
        return locality_tokens.any? { |token| normalized_address.include?(token.gsub(/\s+/, "")) }
      end

      text = doc.text.to_s.gsub(/\s+/, "")
      (company_tokens + locality_tokens).any? { |token| text.include?(token.gsub(/\s+/, "")) }
    end

    def self.branch_tokens(company)
      company.to_s.scan(/\S{1,20}(?:センター|支店|営業所|出張所|オフィス|事業所|本店|本社|支社|工場|店)/)
    end

    def self.address_locality_tokens(address)
      address.to_s.scan(/[^\s　,、。〒]{1,12}(?:市|区|町|村)/).map { |token| token.gsub(/\s+/, "") }
    end
  end
end
