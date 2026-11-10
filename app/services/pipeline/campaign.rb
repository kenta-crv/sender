require "cgi"

module Pipeline
  class Campaign
    HOST = "https://xn--pckua2a7gp15o89zb.com".freeze
    PREFECTURES = %w[
      北海道 青森県 岩手県 宮城県 秋田県 山形県 福島県
      茨城県 栃木県 群馬県 埼玉県 千葉県 東京都 神奈川県
      新潟県 富山県 石川県 福井県 山梨県 長野県 岐阜県
      静岡県 愛知県 三重県 滋賀県 京都府 大阪府 兵庫県
      奈良県 和歌山県 鳥取県 島根県 岡山県 広島県 山口県
      徳島県 香川県 愛媛県 高知県 福岡県 佐賀県 長崎県
      熊本県 大分県 宮崎県 鹿児島県 沖縄県
    ].freeze

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
      "#{HOST}/#{path}"
    end

    def self.area_urls(urls, new_arrival: false)
      Array(urls).flat_map do |url|
        PREFECTURES.map { |prefecture| with_prefecture(url, prefecture, new_arrival: new_arrival) }
      end
    end

    def self.with_prefecture(url, prefecture, new_arrival: false)
      base = URI.decode_www_form_component(URI.parse(url).path.delete_prefix("/"))
      path = CGI.escape("#{base}-#{prefecture}").gsub("+", "%20")
      daily = "#{HOST}/#{path}"
      new_arrival ? "#{daily}?u=1" : daily
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
      self.class.area_urls(search_bases, new_arrival: true)
    end

    def historical_urls
      self.class.area_urls(search_bases, new_arrival: false)
    end

    def backfill_urls
      Array(@config.dig("kyujinbox", "backfill_urls")).map(&:to_s).reject(&:blank?)
    end

    def search_bases
      explicit = backfill_urls
      explicit = Array(@config.dig("kyujinbox", "start_urls")).map(&:to_s).reject(&:blank?) if explicit.empty?
      return explicit if explicit.any?

      keywords.map { |keyword| self.class.keyword_url(keyword) }
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
