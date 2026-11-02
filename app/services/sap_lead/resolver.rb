module SapLead
  class Resolver
    def initialize(client: nil, logger: Rails.logger)
      @client = client
      @logger = logger
    end

    def run
      api = @client || Gbizinfo::Client.new
      stats = { resolved: 0, skipped: 0, errors: 0 }
      JobPosting.where(status: "new").find_each do |posting|
        resolve_one(posting, api, stats)
      end
      @logger.info("[SapLeadResolve] #{stats.inspect}")
      stats
    rescue Gbizinfo::MissingToken => e
      @logger.error("[SapLeadResolve] #{e.message}")
      raise
    end

    private

    def resolve_one(posting, api, stats)
      query_name = CompanyName.tidy(posting.company_raw)
      matches = open_exact_matches(api.search_by_name(query_name), query_name)
      if matches.empty?
        skip(posting, "法人番号なし")
        stats[:skipped] += 1
        return
      end
      if matches.size > 1
        skip(posting, "同名複数")
        stats[:skipped] += 1
        return
      end

      detail = api.basic_info(matches.first["corporate_number"])
      if detail.blank? || closed?(detail)
        skip(posting, "法人番号なし")
        stats[:skipped] += 1
        return
      end

      url = usable_url(detail["company_url"])
      posting.update!(
        corporate_number: detail["corporate_number"].presence || matches.first["corporate_number"],
        official_name: detail["name"].presence || matches.first["name"],
        headquarters_address: detail["location"],
        official_url: url,
        status: "resolved",
        classified_at: Time.current
      )
      stats[:resolved] += 1
    rescue Gbizinfo::MissingToken
      raise
    rescue StandardError => e
      stats[:errors] += 1
      @logger.error("[SapLeadResolve] job_posting=#{posting.id} #{e.class}: #{e.message}")
    end

    def open_exact_matches(rows, query_name)
      target = CompanyName.normalize(query_name)
      Array(rows).select do |row|
        next false if closed?(row)

        CompanyName.normalize(row["name"]) == target
      end
    end

    def closed?(row)
      row["status"].to_s == "閉鎖" || row["close_date"].present?
    end

    # 長い方を先に見る。/jp/ が /jp/ja/ を先に切らないようにする。
    LOCALE_PREFIXES = %w[/jp/ja/ /global/ja/ /ja_jp/ /jp/ /ja/].freeze

    def usable_url(url)
      value = url.to_s.strip
      return nil if value.blank?
      return nil unless value.match?(%r{\Ahttps?://}i)
      return nil if blocked_url?(value)

      uri = URI.parse(value)
      return nil if uri.host.blank?

      path = uri.path.to_s
      return nil if path.match?(/\.pdf\z/i)
      return value if path.include?("/group/")

      locale = LOCALE_PREFIXES.find { |prefix| path.start_with?(prefix) || path == prefix.delete_suffix("/") }
      kept_path = locale || "/"
      URI::Generic.build(scheme: uri.scheme, host: uri.host, path: kept_path).to_s
    rescue URI::InvalidURIError
      nil
    end

    def blocked_url?(url)
      host = URI.parse(url).host.to_s.downcase.sub(/\Awww\./, "")
      return true if host.blank?

      patterns = defined?(BLOCKED_URL_PATTERNS) ? BLOCKED_URL_PATTERNS : []
      patterns.any? { |pattern| host == pattern || host.end_with?(".#{pattern}") || url.downcase.include?(pattern.downcase) }
    rescue URI::InvalidURIError
      true
    end

    def skip(posting, reason)
      posting.update!(status: "skipped", skip_reason: reason, classified_at: Time.current)
    end
  end
end
