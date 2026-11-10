require "cgi"

module Pipeline
  class Campaign
    HOST = "https://xn--pckua2a7gp15o89zb.com".freeze

    attr_reader :key

    def self.all
      raw = yaml
      (raw["campaigns"] || {}).map { |key, config| new(key, config) }
    end

    def self.find(key)
      return nil if key.blank?

      all.find { |campaign| campaign.key == key.to_s }
    end

    def self.sap
      find("sap") || raise("SAPのキャンペーン設定がありません")
    end

    def self.cross_send_interval
      days = yaml["cross_send_interval_days"].to_i
      days = 14 if days <= 0
      days.days
    end

    def self.keyword_url(keyword)
      path = CGI.escape("#{keyword}の仕事").gsub("+", "%20")
      "#{HOST}/#{path}?u=1"
    end

    def self.yaml
      YAML.safe_load(Rails.root.join("config/sap_pipeline.yml").read) || {}
    end

    def initialize(key, config)
      @key = key.to_s
      @config = config || {}
    end

    def name
      @config["name"].to_s
    end

    def group
      @config["group"].to_s
    end

    def business
      @config["business"].to_s
    end

    def sap?
      key == "sap"
    end

    def url
      @config["url"].to_s.presence
    end

    def serp_daily_limit
      value = @config["serp_daily_limit"]
      return nil if value.blank?

      value.to_i
    end

    def ignore_forbidden_text?
      @config["ignore_forbidden_text"] == true
    end

    def exclude_existing_clients?
      @config["exclude_existing_clients"] == true
    end

    def exclude_words
      Array(@config["exclude_words"]).map(&:to_s).reject(&:blank?)
    end

    def title_keywords
      raw = @config.key?("title_keywords") ? @config["title_keywords"] : @config.dig("kyujinbox", "title_keywords")
      Array(raw).map { |keyword| keyword.to_s.unicode_normalize(:nfkc).upcase }.reject(&:blank?).uniq
    end

    def keywords
      Array(@config["keywords"]).map(&:to_s).reject(&:blank?)
    end

    def start_urls
      explicit = Array(@config.dig("kyujinbox", "start_urls")).map(&:to_s).reject(&:blank?)
      return explicit if explicit.any?

      keywords.map { |keyword| self.class.keyword_url(keyword) }
    end

    def backfill_urls
      Array(@config.dig("kyujinbox", "backfill_urls")).map(&:to_s).reject(&:blank?)
    end

    def admin_id
      return SapPipeline.admin_id if sap?

      integer(@config["admin_id"])
    end

    def submission_id
      return SapPipeline.submission_id if sap?

      integer(@config["submission_id"])
    end

    def self.in_group(group)
      all.select { |campaign| campaign.group == group.to_s }
    end

    private

    def integer(value)
      text = value.to_s
      return if text.blank?

      Integer(text, exception: false)
    end
  end
end
