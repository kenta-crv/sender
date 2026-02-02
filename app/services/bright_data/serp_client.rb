# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "cgi"
require "openssl"

module BrightData
  class SerpClient
    ENDPOINT = "https://api.brightdata.com/request"
# app/services/bright_data/serp_client.rb
module BrightData
  class SerpClient
    ENDPOINT = "https://api.brightdata.com/request"

    def initialize(api_key:, zone:)
      @api_key = api_key
      @zone = zone
    end

    def search(query:)
      uri = URI(ENDPOINT)

      req = Net::HTTP::Post.new(uri)
      req["Authorization"] = "Bearer #{@api_key}"
      req["Content-Type"] = "application/json"

      req.body = {
        zone: @zone,
        url: "https://www.google.com/search?q=#{URI.encode_www_form_component(query)}",
        format: "json",
        parse: true
      }.to_json

      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        http.request(req)
      end

      JSON.parse(res.body)
    end
  end
end

    def initialize(api_key:, zone:)
      @api_key = api_key
      @zone = zone
    end

    def search(query:)
      uri = URI(ENDPOINT)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true

      # ★ 重要：SSL検証を無効化（ローカル実行用）
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"]  = "application/json"
      request["Accept"]        = "application/json"

      request.body = {
        zone: @zone,
        url: "https://www.google.com/search?q=#{CGI.escape(query)}",
        format: "json"
      }.to_json

      response = http.request(request)

      JSON.parse(response.body)
    end
  end
end
