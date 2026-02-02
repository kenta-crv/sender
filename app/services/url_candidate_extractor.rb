# frozen_string_literal: true

class UrlCandidateExtractor
  EXCLUDE_KEYWORDS = %w[
    wantedly indeed en-gage rikunabi mynavi
    recruit job career 求人 採用
    prtimes
    twitter facebook instagram
    google.com/maps
  ].freeze

  def self.extract(serp_response)
    items = serp_response.dig("organic_results") || []

    urls = items.map { |i| i["link"] }.compact

    urls.reject do |url|
      EXCLUDE_KEYWORDS.any? { |kw| url.include?(kw) }
    end
  end
end
