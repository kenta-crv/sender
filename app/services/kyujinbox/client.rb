module Kyujinbox
  class Client
    class NotFound < StandardError; end

    def get(url, limit: 5)
      raise "リダイレクトが多すぎます: #{url}" if limit <= 0

      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 10
      http.read_timeout = 10
      request = Net::HTTP::Get.new(uri)
      request["User-Agent"] = USER_AGENT
      request["Accept-Language"] = "ja"

      response = http.request(request)
      case response
      when Net::HTTPRedirection
        location = URI.join(url, response["location"].to_s).to_s
        get(location, limit: limit - 1)
      when Net::HTTPSuccess
        response.body.to_s.dup.force_encoding("UTF-8")
      when Net::HTTPNotFound
        raise NotFound, url
      else
        raise "求人ボックスの取得に失敗しました: #{response.code} #{url}"
      end
    end
  end
end
