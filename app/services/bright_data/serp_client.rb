# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "cgi"
require "openssl"

module BrightData
  class SerpClient
    ENDPOINT = "https://api.brightdata.com/request"
    MAX_RETRIES = 3
    BASE_DELAY = 2  # seconds（指数バックオフの基底）

    def initialize(api_key: nil, zone: nil)
      @api_key = api_key || ENV['BRIGHT_DATA_API_KEY']
      @zone = zone || ENV['BRIGHT_DATA_ZONE']

      raise ArgumentError, "BRIGHT_DATA_API_KEY が未設定" if @api_key.blank?
      raise ArgumentError, "BRIGHT_DATA_ZONE が未設定" if @zone.blank?
    end

    # --- 単一クエリ ---
    # @param query [String] 検索キーワード
    # @param gl [String] 国コード（デフォルト: jp）
    # @param hl [String] 言語コード（デフォルト: ja）
    # @return [Hash] パース済みレスポンス。エラー時は { error: message } を含む
    def search(query:, gl: "jp", hl: "ja")
      encoded = CGI.escape(query)
      target_url = "https://www.google.com/search?q=#{encoded}&gl=#{gl}&hl=#{hl}&brd_json=1"

      retries = 0
      begin
        raw = execute_request(target_url)
        parsed = JSON.parse(raw, symbolize_names: false)

        # Bright Data がエラーを返す場合のチェック
        if parsed.is_a?(Hash) && parsed["error"]
          log(:warn, "API returned error for '#{query}': #{parsed['error']}")
          return { "error" => parsed["error"], "query" => query }
        end

        parsed
      rescue Net::ReadTimeout, Net::OpenTimeout => e
        retries += 1
        if retries <= MAX_RETRIES
          delay = BASE_DELAY ** retries
          log(:warn, "Timeout retry #{retries}/#{MAX_RETRIES} for '#{query}', waiting #{delay}s")
          sleep(delay)
          retry
        end
        log(:error, "Failed after #{MAX_RETRIES} retries for '#{query}': #{e.message}")
        { "error" => "timeout after #{MAX_RETRIES} retries", "query" => query }
      rescue JSON::ParserError => e
        log(:error, "JSON parse error for '#{query}': #{e.message}")
        { "error" => "json_parse_error", "query" => query, "raw_preview" => raw&.to_s&.first(200) }
      rescue => e
        retries += 1
        if retries <= MAX_RETRIES
          delay = BASE_DELAY ** retries
          log(:warn, "Error retry #{retries}/#{MAX_RETRIES} for '#{query}': #{e.message}")
          sleep(delay)
          retry
        end
        log(:error, "Unrecoverable error for '#{query}': #{e.class} #{e.message}")
        { "error" => e.message, "query" => query }
      end
    end

    # --- バッチ実行 ---
    # @param queries [Array<String>] キーワード配列
    # @param delay_between [Integer] リクエスト間の待機秒数
    # @return [Array<Hash>] { query:, result:, timestamp: } の配列
    def batch_search(queries, delay_between: 1)
      results = []
      total = queries.size

      queries.each_with_index do |query, idx|
        log(:info, "Processing #{idx + 1}/#{total}: #{query}")
        result = search(query: query)
        results << {
          "query" => query,
          "result" => result,
          "timestamp" => Time.current.iso8601
        }
        sleep(delay_between) unless idx == total - 1
      end

      results
    end

    private

    def execute_request(target_url)
      uri = URI(ENDPOINT)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.ssl_version = :TLSv1_2
      ssl_context = OpenSSL::SSL::SSLContext.new
      ssl_context.verify_flags = OpenSSL::SSL::OP_NO_SSLv2 | OpenSSL::SSL::OP_NO_SSLv3
      # Bright Data APIのCRL検証エラー回避
      ssl_context.verify_mode = OpenSSL::SSL::VERIFY_PEER
      ssl_context.cert_store = OpenSSL::X509::Store.new.tap do |store|
        store.set_default_paths
        store.flags = OpenSSL::X509::V_FLAG_PARTIAL_CHAIN
      end
      http.read_timeout = 30
      http.open_timeout = 10

      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"
      request["Accept"] = "application/json"

      request.body = {
        zone: @zone,
        url: target_url,
        format: "raw"
      }.to_json

      response = http.request(request)

      unless response.is_a?(Net::HTTPSuccess)
        raise "HTTP #{response.code}: #{response.body&.first(300)}"
      end

      response.body
    end

    def log(level, message)
      msg = "[BrightData::SerpClient] #{message}"
      if defined?(Rails)
        Rails.logger.send(level, msg)
      end
      puts msg
    end
  end
end
