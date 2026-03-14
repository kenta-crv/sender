# frozen_string_literal: true

module BrightData
  class CompanyExtractor
    # ★ クライアント提供の業種リストに差し替えること
    TARGET_INDUSTRIES = %w[
      IT Web システム ソフトウェア 情報
      コンサルティング 広告 人材 不動産
      建設 製造 飲食 医療 教育
    ].freeze

    # 既存の除外パターン（url_candidate_extractor.rb から流用）
    EXCLUDE_URL_KEYWORDS = %w[
      wantedly indeed en-gage rikunabi mynavi
      recruit job career 求人 採用
      prtimes twitter facebook instagram
      google.com/maps wikipedia
      hellowork.mhlw.go.jp
      baseconnect.in navitime.co.jp
      .pdf .xlsx .csv
      city. pref. go.jp soumu
      lobbymap seidanren
    ].freeze

    # SERP結果1件分から企業情報を抽出
    # ★ キー名（"organic_results" vs "organic" 等）はDay1の確認結果に合わせて修正
    def self.extract(serp_result, query: nil)
      companies = []

      # 1. organic_results（メインのGoogle検索結果）
      organics = serp_result["organic_results"] || serp_result["organic"] || []
      organics.first(10).each do |item|
        url = item["link"].to_s
        next if url.blank?
        next if excluded_url?(url)

        companies << {
          company: parse_company_name(item["title"]),
          tel: nil, address: nil,
          url: url, contact_url: nil,
          industry: nil, source: "organic", query: query
        }
      end

      # 2. local_results（Google Maps結果）
      locals = serp_result["local_results"] || []
      locals.each do |item|
        companies << {
          company: item["title"].to_s.strip,
          tel: item["phone"].to_s.strip.presence,
          address: item["address"].to_s.strip.presence,
          url: (item["link"] || item["website"]).to_s.strip.presence,
          contact_url: nil,
          industry: (item["type"] || item["category"]).to_s.strip.presence,
          source: "local", query: query
        }
      end

      # 3. knowledge_graph
      if (kg = serp_result["knowledge_graph"])
        companies << {
          company: kg["title"].to_s.strip,
          tel: kg["phone"].to_s.strip.presence,
          address: kg["address"].to_s.strip.presence,
          url: (kg["website"] || kg["link"]).to_s.strip.presence,
          contact_url: nil,
          industry: kg["type"].to_s.strip.presence,
          source: "knowledge_graph", query: query
        }
      end

      companies.uniq { |c| c[:url] }.then { |cs| filter_by_industry(cs) }
    end

    def self.extract_batch(batch_results)
      batch_results.flat_map { |b| extract(b["result"], query: b["query"]) }
    end

    private

    def self.parse_company_name(title)
      return nil if title.blank?
      parts = title.split(%r{\s*[|\-｜—–／/]\s*})
      corp = parts.find { |p| p.match?(/株式会社|有限会社|合同会社|一般社団法人/) }
      (corp || parts.first).to_s.strip.presence
    end

    def self.excluded_url?(url)
      EXCLUDE_URL_KEYWORDS.any? { |kw| url.downcase.include?(kw.downcase) }
    end

    def self.filter_by_industry(companies)
      companies.select do |c|
        c[:industry].nil? || TARGET_INDUSTRIES.any? { |t| c[:industry].include?(t) }
      end
    end
  end
end
