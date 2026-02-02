require "nokogiri"
require "uri"

module GoogleSearch
  class Parser
    EXCLUDE_DOMAINS = %w[
      indeed.com
      en-japan.com
      mynavi.jp
      rikunabi.com
      wantedly.com
      career
      job
      recruit
      map
      news
    ]

    def initialize(html)
      @doc = Nokogiri::HTML(html)
    end

    def organic_links
      @doc.css("a").map do |a|
        href = a["href"]
        next unless href&.start_with?("/url?q=")

        url = href.split("/url?q=").last.split("&").first
        next unless url.start_with?("http")

        uri = URI.parse(url)
        next if exclude?(uri.host)

        url
      rescue
        nil
      end.compact.uniq
    end

    private

    def exclude?(host)
      return true if host.nil?
      EXCLUDE_DOMAINS.any? { |d| host.include?(d) }
    end
  end
end
