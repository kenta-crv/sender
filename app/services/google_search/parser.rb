require "nokogiri"
require "uri"

module GoogleSearch
  class Parser
    def initialize(html)
      @doc = Nokogiri::HTML(html)
    end

    def organic_links
      @doc.css("a").map do |a|
        href = a["href"]
        next unless href&.start_with?("/url?q=")

        url = href.split("/url?q=").last.split("&").first
        next unless url.start_with?("http")

        next if BrightData::UrlPolicy.excluded_url?(url, title: a.text)

        url
      rescue
        nil
      end.compact.uniq
    end
  end
end
