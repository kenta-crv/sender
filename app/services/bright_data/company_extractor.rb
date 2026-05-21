# frozen_string_literal: true

require "uri"

module BrightData
  # === 業種（industry）抽出ロジックについて ===
  #
  # 現状、業種は以下の限定的なソースからしか取得できない:
  #   - SERP local_results の "type" / "category"   ← Google Maps カード相当
  #   - SERP knowledge_graph の "type"              ← ナレッジパネル相当
  #
  # organic_results（通常の Web 検索結果）からは業種は取得していない（常に nil）。
  # WebEnricher（HTMLクロール）も業種抽出は実装していない。
  # business / genre カラムは本パイプラインでは一切セットされず、
  # 既存の手動入力 / 別フローで設定された値を保持するのみ。
  #
  # → 取引先向け補足:
  #   B2B 検索（"〇〇株式会社 会社概要" など）では SERP の local_results /
  #   knowledge_graph がヒットしないクエリが大半のため、
  #   industry が埋まる確率は低いのが想定動作です。
  #   業種を網羅的に補完したい場合は、HTML から
  #   meta keywords / panhkuzu / 業種別ディレクトリ等を
  #   推定する別ロジックの実装が必要です。
  class CompanyExtractor
    # organic_results から採用する上位件数（BrightData コスト削減と精度向上のため）
    MAX_ORGANIC_RESULTS = 5
    LEGAL_ENTITY_PATTERN = /株式会社|有限会社|合同会社|一般社団法人|一般財団法人|社会福祉法人|医療法人|学校法人/.freeze
    GENERIC_TITLE_PATTERN = /\A(?:会社概要|会社情報|会社案内|企業情報|企業概要|About(?: us)?|Overview|Company|トップページ|ホーム)\z/i.freeze
    GENERIC_PROFILE_PATH_PATTERN = %r{/(?:company|about|profile)(?:/|[-_a-z]*\.html?|$)}i.freeze
    PREFECTURE_PATTERN = /東京都|大阪府|北海道|神奈川県|愛知県|福岡県|埼玉県|千葉県|兵庫県|静岡県|茨城県|広島県|京都府|宮城県|新潟県|長野県|岐阜県|群馬県|栃木県|岡山県|福島県|三重県|熊本県|鹿児島県|沖縄県|滋賀県|山口県|愛媛県|長崎県|奈良県|青森県|岩手県|大分県|石川県|山形県|宮崎県|富山県|秋田県|香川県|和歌山県|佐賀県|福井県|徳島県|高知県|島根県|鳥取県|山梨県/.freeze

    # ★ クライアント提供の業種リストに差し替えること
    TARGET_INDUSTRIES = %w[
      IT Web システム ソフトウェア 情報
      コンサルティング 広告 人材 不動産
      建設 製造 飲食 医療 教育
    ].freeze

    # SERP結果1件分から企業情報を抽出
    # ★ キー名（"organic_results" vs "organic" 等）はDay1の確認結果に合わせて修正
    def self.extract(serp_result, query: nil)
      companies = []

      # 1. organic_results（メインのGoogle検索結果）
      organics = serp_result["organic_results"] || serp_result["organic"] || []
      generic_fallback_used = false
      organics.first(MAX_ORGANIC_RESULTS).each_with_index do |item, idx|
        url = item["link"].to_s
        title = item["title"].to_s
        next if url.blank?
        next if UrlPolicy.excluded_url?(url, title: title)

        company_name = parse_company_name(title, query: query, allow_generic_fallback: idx < 2, allow_title_fallback: false)
        company_name ||= generic_profile_company_name(title, url, query, idx)
        company_name ||= query_company_profile_name(title, url, query, idx)
        company_name ||= query_company_location_page_name(title, url, query, idx)
        generic_fallback = company_name.present? &&
                           generic_title_only?(title) &&
                           company_name == query_company_name(query)
        next if generic_fallback && generic_fallback_used
        generic_fallback_used ||= generic_fallback
        next if company_name.blank?

        companies << {
          company: company_name,
          title: title,
          tel: nil, address: nil,
          url: url, contact_url: nil,
          industry: nil, source: "organic", query: query
        }
      end

      # 2. local_results（Google Maps結果）
      locals = serp_result["local_results"] || []
      locals.each do |item|
        url = (item["link"] || item["website"]).to_s.strip.presence
        title = item["title"].to_s.strip
        companies << {
          company: parse_company_name(title),
          title: title,
          tel: item["phone"].to_s.strip.presence,
          address: item["address"].to_s.strip.presence,
          url: UrlPolicy.official_url?(url, title: title) ? url : nil,
          contact_url: nil,
          industry: (item["type"] || item["category"]).to_s.strip.presence,
          source: "local", query: query
        }
      end

      # 3. knowledge_graph
      if (kg = serp_result["knowledge_graph"])
        url = (kg["website"] || kg["link"]).to_s.strip.presence
        title = kg["title"].to_s.strip
        companies << {
          company: parse_company_name(title),
          title: title,
          tel: kg["phone"].to_s.strip.presence,
          address: kg["address"].to_s.strip.presence,
          url: UrlPolicy.official_url?(url, title: title) ? url : nil,
          contact_url: nil,
          industry: kg["type"].to_s.strip.presence,
          source: "knowledge_graph", query: query
        }
      end

      companies.uniq { |c| c[:url].presence || [c[:company], c[:source], c[:address]] }.then { |cs| filter_by_industry(cs, query: query) }
    end

    def self.extract_batch(batch_results)
      batch_results.flat_map { |b| extract(b["result"], query: b["query"]) }
    end

    private

    def self.parse_company_name(title, query: nil, allow_generic_fallback: true, allow_title_fallback: true)
      return nil if title.blank?

      parts = title.to_s.split(%r{\s*[|\-｜—–―／/]\s*})
                   .filter_map { |part| UrlPolicy.normalize_company_name(part) }
      corp = parts.find { |p| p.match?(LEGAL_ENTITY_PATTERN) }
      return sanitize_company_name(corp).presence if corp.present?

      query_name = query_company_name(query)
      return query_name if query_name.present? && title_matches_query_company?(title, query_name)
      return query_name if allow_generic_fallback && generic_title_only?(title) && query_name.to_s.match?(LEGAL_ENTITY_PATTERN)

      return nil unless allow_title_fallback

      UrlPolicy.normalize_company_name(title).presence || parts.first.to_s.strip.presence
    end

    def self.filter_by_industry(companies, query: nil)
      companies.select do |c|
        if query.present? && c[:company].present? && c[:source] == "organic"
          next false unless matches_query_company?(c[:company], query)
        end

        c[:industry].nil? || TARGET_INDUSTRIES.any? { |t| c[:industry].include?(t) }
      end
    end

    def self.query_company_name(query)
      return nil if query.blank?

      query.to_s
           .sub(/\s+#{PREFECTURE_PATTERN}.*\z/, "")
           .sub(/\s+会社概要\z/, "")
           .then { |name| strip_trailing_location_suffix(name) }
           .strip
           .presence
    end

    def self.generic_title_only?(title)
      return false if title.blank?

      parts = title.to_s.split(%r{\s*[|\-｜—–―／/]\s*})
      parts.first.to_s.strip.match?(GENERIC_TITLE_PATTERN) && parts.none? { |part| part.match?(LEGAL_ENTITY_PATTERN) }
    end

    def self.strip_trailing_location_suffix(name)
      value = name.to_s.strip
      return value unless value.match?(LEGAL_ENTITY_PATTERN)

      value.sub(/\s+[^\s]*(?:都|道|府|県|市|区|町|村)(?:\s.*)?\z/, "")
    end

    def self.generic_profile_company_name(title, url, query, index)
      return nil unless index.to_i < 2
      return nil unless generic_title_only?(title)
      return nil unless profile_like_url?(url)

      company_name = query_company_name(query)
      return nil if company_name.blank?
      return nil if WebEnricher.send(:normalize_company, company_name).length < 4

      company_name
    end

    def self.query_company_profile_name(title, url, query, index)
      return nil unless index.to_i < 2
      return nil unless profile_like_url?(url)
      return nil if title.to_s.match?(/求人|採用|転職|バイト|アルバイト|パート/)

      company_name = query_company_name(query)
      return nil if company_name.blank?
      return nil unless company_name.match?(LEGAL_ENTITY_PATTERN)
      return nil if WebEnricher.send(:normalize_company, company_name).length < 4

      company_name
    end

    def self.query_company_location_page_name(title, url, query, index)
      return nil unless index.to_i < MAX_ORGANIC_RESULTS
      return nil unless location_page_url?(url)
      return nil if title.to_s.match?(/求人|採用|転職|バイト|アルバイト|パート/)

      company_name = query_company_name(query)
      return nil if company_name.blank?
      return nil unless company_name.match?(LEGAL_ENTITY_PATTERN)
      return nil if WebEnricher.send(:normalize_company, company_name).length < 4

      title_core = normalize_company_core(title).delete(" 　").downcase
      query_core = normalize_company_core(company_name).delete(" 　").downcase
      full_query_core = normalize_company_core(query).delete(" 　").downcase
      return nil if title_core.length < 4
      return nil unless query_core.include?(title_core) ||
                        title_core.include?(query_core) ||
                        full_query_core.include?(title_core)

      company_name
    end

    def self.profile_like_url?(url)
      path = URI.parse(url.to_s).path.to_s
      path.match?(GENERIC_PROFILE_PATH_PATTERN) ||
        path.match?(%r{/(?:company|about|profile|corporate|outline|gaiyo|gaiyou|kaisha)(?:/|[-_a-z]*\.html?|$)}i)
    rescue URI::InvalidURIError
      false
    end

    def self.location_page_url?(url)
      path = URI.parse(url.to_s).path.to_s
      path.match?(%r{/(?:facility|shop|office|branch|store)(?:/|[-_a-z]*\.html?|$)}i)
    rescue URI::InvalidURIError
      false
    end

    def self.normalize_company_core(value)
      value.to_s.gsub(/[輛輌]/, "両").gsub(LEGAL_ENTITY_PATTERN, "").gsub(/\s+/, " ").strip
    end

    def self.title_matches_query_company?(title, query_name)
      title_core = normalize_company_core(title).downcase
      query_core = normalize_company_core(query_name).downcase
      return false if title_core.blank? || query_core.blank?

      title_core.delete(" 　").include?(query_core.delete(" 　"))
    end

    def self.matches_query_company?(company, query)
      query_core = normalize_company_core(query_company_name(query) || query)
      company_core = normalize_company_core(company)
      return false if query_core.blank? || company_core.blank?

      query_compact = query_core.delete(" 　").downcase
      company_compact = company_core.delete(" 　").downcase

      if query_compact.match?(/\A[A-Za-z0-9&.]{1,4}\z/)
        company_compact.casecmp?(query_compact)
      else
        company_compact.include?(query_compact) || query_compact.include?(company_compact)
      end
    end

    def self.sanitize_company_name(name)
      legal = LEGAL_ENTITY_PATTERN.source
      text = name.to_s.strip
      bracketed = text.match(/[【\[]\s*((?:#{legal})[^】\]]{1,40})[】\]]/)
      text = bracketed[1].strip if bracketed
      text = text.sub(/\A.*の((?:#{legal}).*)\z/, "\\1")
      corp = text.match(/(?:#{legal})\s*[A-Za-z0-9一-龥ァ-ヶー&.\s]{1,40}/)
      text = corp[0].strip if corp
      text.sub(/[（(].*\z/, "")
          .sub(/の(?:会社概要|企業情報|採用情報|求人情報|評判|口コミ|転職).*\z/, "")
          .sub(/【.*\z/, "")
          .sub(/[】\]].*\z/, "")
          .sub(/(?:求人|採用|配達|配送).*\z/, "")
          .strip
    end
  end
end
