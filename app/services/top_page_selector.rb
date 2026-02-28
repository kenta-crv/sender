# frozen_string_literal: true

require "net/http"
require "nokogiri"

class TopPageSelector
  PROFILE_PATHS = %w[
    /company /about /profile /company-profile
    /会社概要 /企業情報
  ].freeze

  def self.select(urls)
    urls.each do |url|
      next unless html_contains_profile_link?(url)
      return url
    end
    urls.first
  end

  def self.html_contains_profile_link?(url)
    doc = fetch_doc(url)
    PROFILE_PATHS.any? do |path|
      doc.css("a").any? { |a| a["href"]&.include?(path) }
    end
  rescue
    false
  end

  def self.fetch_doc(url)
    uri = URI(url)
    res = Net::HTTP.get_response(uri)
    Nokogiri::HTML(res.body)
  end
end
