class GeminiPillarGenerator
  require "net/http"
  require "json"
  require "openssl"

  GEMINI_API_KEY = ENV["GEMINI_API_KEY"]
  GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
  MAX_RETRIES = 3
  MAX_PILLARS_PER_GENRE = 10

  GENRE_CONFIG = GeminiColumnGenerator::GENRE_CONFIG

  def self.generate_pillars(genre: nil, batch_count: 10)
    success_count = 0
    genre_list = genre ? [genre.to_sym] : GENRE_CONFIG.keys.shuffle
    processed = 0

    while processed < batch_count
      genre_list.each do |g|
        break if processed >= batch_count

        count = Column.where(genre: g.to_s, article_type: "pillar").count
        if count >= MAX_PILLARS_PER_GENRE
          puts "⚠️ [#{g}] 親記事上限(#{MAX_PILLARS_PER_GENRE})到達"
          next
        end

        target_category = GENRE_CONFIG[g][:categories].sample
        success_count += 1 if execute_generation(g, target_category)
        processed += 1
        sleep 3
      end
      genre_list.shuffle!
    end

    puts "\n✅ 完了: #{success_count} / #{batch_count} 件の親記事を保存しました"
    success_count
  end

  def self.execute_generation(genre, target_category)
    puts "\n--- [#{genre}] 親記事生成開始 カテゴリ: #{target_category} ---"

    config = GENRE_CONFIG[genre]

    prompt = <<~PROMPT
      以下の条件に基づき、SEOに強い「親記事（pillar記事）」のメタ情報を作成してください。
      出力は必ず「1つのJSONオブジェクトのみ」とし、配列 [] は使用しないでください。

      【サービス情報】
      サービス名: #{config[:service_name]} (#{config[:service_brand]})
      サービスURL: #{config[:service_path]}
      ターゲット: #{config[:target]}
      カテゴリー: #{target_category}
      除外対象: #{config[:exclude]}

      【親記事の要件】
      ・ジャンル全体を包括するテーマであること
      ・複数の子記事を束ねる起点になる設計であること
      ・SEOを意識し、検索ニーズの広いテーマであること
      ・#{config[:service_name]}の専門領域に深く合致していること
      ・#{config[:exclude]}向けの内容にならないこと

      【出力JSON形式（必ず1つだけ）】
      {
        "title": "親記事にふさわしい包括的なタイトル",
        "code": "url-slug-text",
        "description": "120文字程度の要約",
        "keyword": "主要キーワード1, 主要キーワード2"
      }
    PROMPT

    retries = 0

    loop do
      response_text = post_to_gemini(prompt)
      return false if response_text.nil?

      json_match = response_text.match(/(\{.*\})/m)
      json_text = json_match ? json_match[0] : nil

      if json_text.nil?
        puts "❌ JSON抽出失敗"
        retries += 1
        break if retries >= MAX_RETRIES
        next
      end

      begin
        data = JSON.parse(json_text)

        required = %w[title code description keyword]
        missing = required.select { |k| data[k].to_s.strip.empty? }

        if missing.empty?
          Column.create!(
            title: data["title"],
            code: data["code"],
            description: data["description"],
            keyword: data["keyword"],
            choice: target_category,
            genre: genre.to_s,
            status: "draft",
            article_type: "pillar"
          )

          puts "✅ 保存成功: #{data["title"]}"
          return true
        else
          puts "❌ キー欠損: #{missing}"
        end

      rescue JSON::ParserError => e
        puts "❌ JSONパースエラー: #{e.message}"
        puts "【データ冒頭】#{json_text[0..100]}..."
      end

      retries += 1
      break if retries >= MAX_RETRIES
    end

    false
  end

  def self.post_to_gemini(prompt)
    uri = URI(GEMINI_API_URL)
    uri.query = URI.encode_www_form(key: GEMINI_API_KEY)

    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    req.body = {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        response_mime_type: "application/json"
      }
    }.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    return nil unless res.is_a?(Net::HTTPSuccess)

    body = JSON.parse(res.body)
    body.dig("candidates", 0, "content", "parts", 0, "text")
  rescue => e
    puts "❌ API通信エラー: #{e.message}"
    nil
  end
end
