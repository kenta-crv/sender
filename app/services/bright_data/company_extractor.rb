# frozen_string_literal: true

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
      organics.first(MAX_ORGANIC_RESULTS).each do |item|
        url = item["link"].to_s
        title = item["title"].to_s
        next if url.blank?
        next if UrlPolicy.excluded_url?(url, title: title)

        companies << {
          company: parse_company_name(title),
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
          tel: kg["phone"].to_s.strip.presence,
          address: kg["address"].to_s.strip.presence,
          url: UrlPolicy.official_url?(url, title: title) ? url : nil,
          contact_url: nil,
          industry: kg["type"].to_s.strip.presence,
          source: "knowledge_graph", query: query
        }
      end

      companies.uniq { |c| c[:url].presence || [c[:company], c[:source], c[:address]] }.then { |cs| filter_by_industry(cs) }
    end

    def self.extract_batch(batch_results)
      batch_results.flat_map { |b| extract(b["result"], query: b["query"]) }
    end

    private

    def self.parse_company_name(title)
      return nil if title.blank?

      normalized = UrlPolicy.normalize_company_name(title)
      parts = normalized.to_s.split(%r{\s*[|\-｜—–／/]\s*})
      corp = parts.find { |p| p.match?(/株式会社|有限会社|合同会社|一般社団法人/) }
      (corp || parts.first).to_s.strip.presence
    end

    def self.filter_by_industry(companies)
      companies.select do |c|
        c[:industry].nil? || TARGET_INDUSTRIES.any? { |t| c[:industry].include?(t) }
      end
    end
  end
end
