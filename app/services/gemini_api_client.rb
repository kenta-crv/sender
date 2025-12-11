# app/services/concerns/gemini_api_client.rb
# 共通のGemini API通信処理を担うモジュール

module GeminiApiClient
  require "net/http"
  require "json"
  require "openssl"
  extend ActiveSupport::Concern # Rails環境でモジュールを利用するための定型句

  GEMINI_API_KEY = ENV["GEMINI_API_KEY"]
  GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

  # APIへのリクエストを送信し、結果のテキスト部分を返す
  # category_listはJSONスキーマのenum制約を設定するために使用
  def self.post_to_gemini(prompt, category_list = nil)
    uri = URI(GEMINI_API_URL)
    uri.query = URI.encode_www_form(key: GEMINI_API_KEY)

    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")

    category_schema = { "type": "string" }
    category_schema["enum"] = category_list if category_list.present? 

    req.body = {
      contents: [ { parts: [ { text: prompt } ] } ],
      generationConfig: {
        "responseMimeType": "application/json",
        "responseSchema": {
          "type": "object",
          "properties": {
            "title":       { "type": "string" },
            "description": { "type": "string" },
            "keyword":     { "type": "string" },
            "category":    category_schema
          },
          "required": ["title", "description", "keyword", "category"]
        }
      }
    }.to_json

    # 504対策：read_timeoutを120秒に延長
    res = Net::HTTP.start(uri.hostname, uri.port, 
                          use_ssl: true, 
                          verify_mode: OpenSSL::SSL::VERIFY_NONE,
                          read_timeout: 120) do |http| 
      http.request(req)
    end

    if res.is_a?(Net::HTTPSuccess)
      api_response = JSON.parse(res.body)
      # コンテンツのテキスト部分を返す
      api_response.dig("candidates", 0, "content", "parts", 0, "text")
    else
      Rails.logger.error("Gemini API error (Status: #{res.code}): #{res.body}")
      nil
    end
  end
end