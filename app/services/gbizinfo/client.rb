module Gbizinfo
  class MissingToken < StandardError; end

  # gBizINFO REST API v2
  # 検索: GET /v2/hojin?name= （部分一致）。存続判定は応答の status / close_date。
  # 基本情報: GET /v2/hojin/{法人番号} の company_url / location / name。
  class Client
    BASE_URL = "https://api.info.gbiz.go.jp/hojin/v2/hojin".freeze

    def initialize(token: ENV["GBIZINFO_API_TOKEN"], http: Net::HTTP)
      @token = token.to_s
      @http = http
    end

    def search_by_name(name)
      get(BASE_URL, name: name, limit: 100)
    end

    def basic_info(corporate_number)
      infos = get("#{BASE_URL}/#{corporate_number}")
      infos.first
    end

    private

    def get(url, params = {})
      raise MissingToken, "GBIZINFO_API_TOKEN が未設定です" if @token.blank?

      uri = URI(url)
      uri.query = URI.encode_www_form(params) if params.any?
      request = Net::HTTP::Get.new(uri)
      request["X-hojinInfo-api-token"] = @token
      request["Accept"] = "application/json"
      response = @http.start(uri.host, uri.port, use_ssl: uri.scheme == "https", open_timeout: 10, read_timeout: 20) do |http|
        http.request(request)
      end
      unless response.is_a?(Net::HTTPSuccess)
        raise "gBizINFOの取得に失敗しました: #{response.code} #{url}"
      end

      body = JSON.parse(response.body)
      Array(body["hojin-infos"])
    end
  end
end
