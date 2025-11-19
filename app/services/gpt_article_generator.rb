require "net/http"
require "json"
require "openssl"

class GptArticleGenerator
  # 環境変数からOpenAI API Keyを取得
  GPT_API_KEY = ENV["OPENAI_API_KEY"] 
  GPT_API_URL = "https://api.openai.com/v1/chat/completions"

  def self.generate_body(column)
    # 🚨 STEP 1: APIキーの存在チェック 🚨
    unless GPT_API_KEY.present?
      Rails.logger.error("【致命的エラー】OPENAI_API_KEY が設定されていません。環境変数を確認してください。")
      return nil
    end

    # 記事生成に必要なデータを取り出す
    title = column.title
    description = column.description
    keyword = column.keyword
    category = column.choice # 正しいカラム名 'choice' を使用

    # 記事本文生成用のプロンプトを作成
    prompt = <<~PROMPT
      以下の情報に基づいて、読者の興味を引く魅力的なブログ記事の本文を生成してください。
      - テーマ（タイトル）：#{title}
      - 概要：#{description}
      - メインキーワード：#{keyword}
      - カテゴリ：#{category}

      # 記事構成の指示
      1. 導入：読者の共感を呼び、記事全体への期待感を高める。
      2. 本論：テーマを複数のセクションに分けて深く掘り下げ、具体的な情報や実用的なアドバイスを提供する。
      3. 結論：記事の要点をまとめ、読者への行動喚起（CTA）を含める。
      
      生成される本文は、Markdown形式で、読みやすく整形してください。
    PROMPT

    # 記事生成APIを呼び出す
    response = call_gpt_api(prompt)
    
    # 応答から本文を抽出し、返却
    if response && response["choices"]&.first&.dig("message", "content")
      return response["choices"].first["message"]["content"]
    else
      # API呼び出しに成功したが、本文がnilだった場合（通常は発生しないが念のため）
      Rails.logger.warn("GPT APIから本文が取得できませんでした。レスポンス: #{response.inspect}") if response
      return nil
    end
  end

  private

  def self.call_gpt_api(prompt)
    uri = URI(GPT_API_URL)
    
    # HTTPヘッダーにAPIキーを設定
    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json", "Authorization" => "Bearer #{GPT_API_KEY}")

    req.body = {
      model: "gpt-4o-mini", # 処理速度とコストのバランスが良いモデルに設定
      messages: [
        { role: "system", content: "あなたはプロのコンテンツライターです。ユーザーの指示に従い、高品質な記事を生成してください。" },
        { role: "user", content: prompt }
      ],
      temperature: 0.7
    }.to_json

    begin
      res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
        http.request(req)
      end

      if res.is_a?(Net::HTTPSuccess)
        JSON.parse(res.body)
      else
        # 🚨 STEP 2: APIエラー発生時の詳細ログ出力 🚨
        Rails.logger.error("GPT API error (Status: #{res.code}): #{res.body}")
        nil
      end
    rescue OpenSSL::SSL::SSLError => e
      # SSL/TLS関連のエラーログ
      Rails.logger.error("GPT API 呼び出し中のSSLエラー: #{e.message} (Ruby/OpenSSLのバージョンに依存する可能性があります)")
      nil
    rescue Timeout::Error, Errno::EINVAL, Errno::ECONNRESET, Errno::ECONNREFUSED, EOFError, Net::HTTPBadResponse, Net::HTTPHeaderSyntaxError, Net::ProtocolError => e
      # その他の通信・ネットワークエラー
      Rails.logger.error("GPT API 呼び出し中のネットワークエラー: #{e.message}")
      nil
    end
  end
end