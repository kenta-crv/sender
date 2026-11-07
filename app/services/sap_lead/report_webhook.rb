require "json"
require "net/http"
require "uri"

module SapLead
  class ReportWebhook
    SUCCESS_RESULTS = %w[appended exists].freeze

    def initialize(url: ENV["SAP_REPORT_WEBHOOK_URL"], secret: ENV["SAP_REPORT_WEBHOOK_SECRET"], transport: nil)
      @url = url.to_s
      @secret = secret.to_s
      @transport = transport
    end

    def append_row(row)
      raise "SAP_REPORT_WEBHOOK_URL が未設定です" if @url.blank?
      raise "SAP_REPORT_WEBHOOK_SECRET が未設定です" if @secret.blank?
      raise "週次レポートの列数が26ではありません" unless row.is_a?(Array) && row.size == 26

      response = post_then_get(URI(@url), JSON.generate(secret: @secret, row: row))
      payload = JSON.parse(response.body.to_s)
      result = payload["result"].to_s
      return result.to_sym if SUCCESS_RESULTS.include?(result)

      raise "週次レポートの応答が失敗です: #{result.presence || "empty"}"
    rescue JSON::ParserError
      raise "週次レポートの応答を読めません"
    end

    private

    def post_then_get(uri, body)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = body
      response = execute(request, uri)
      hops = 0
      while redirect?(response) && hops < 5
        location = response["location"].to_s
        raise "週次レポートのリダイレクト先がありません" if location.blank?

        uri = URI.join(uri.to_s, location)
        response = execute(Net::HTTP::Get.new(uri), uri)
        hops += 1
      end
      response
    end

    def execute(request, uri)
      return @transport.call(request, uri) if @transport

      Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 15, read_timeout: 30) do |http|
        http.request(request)
      end
    end

    def redirect?(response)
      (300..399).cover?(response.code.to_i)
    end
  end
end
