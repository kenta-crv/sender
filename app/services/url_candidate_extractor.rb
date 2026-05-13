# frozen_string_literal: true

class UrlCandidateExtractor
  def self.extract(serp_response)
    items = serp_response.dig("organic_results") || []

    items.filter_map do |item|
      url = item["link"].to_s
      next if url.blank?
      next if BrightData::UrlPolicy.excluded_url?(url, title: item["title"])

      url
    end
  end
end
