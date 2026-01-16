class GeminiColumnGenerator
  require "net/http"
  require "json"
  require "openssl"

  GEMINI_API_KEY = ENV["GEMINI_API_KEY"]
  # 最新の安定版モデルを指定
  GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent"
  MAX_RETRIES = 3

  GENRE_CONFIG = {
    cargo: {
      service_name:  "軽貨物配送サービス",
      service_brand: "OK配送",
      service_path:  "/cargo",
      target: "軽貨物事業者との取引や協業を検討している企業の担当者または経営層（荷主企業やITベンダーなど）",
      categories: ["課題解決", "選定・比較", "業界理解", "活用イメージ", "不安解消"],
      exclude: "求職者および軽貨物事業者自身に向けた発信"
    },
    security: {
      service_name:  "警備業務",
      service_brand: "OK警備",
      service_path:  "/security",
      target: "警備業務の外注や切替を検討している企業・施設管理者",
      categories: ["課題解決", "選定・比較", "業界理解", "活用イメージ", "不安解消"],
      exclude: "警備員の求人や資格取得を目的とした発信"
    },
    cleaning: {
      service_name:  "清掃業務",
      service_brand: "OK清掃",
      service_path:  "/cleaning",
      target: "清掃業務の外注を検討している法人・施設管理者",
      categories: ["課題解決", "選定・比較", "業界理解", "活用イメージ", "不安解消"],
      exclude: "清掃スタッフの求人向け発信"
    },
    app: {
      service_name:  "テレアポ型営業代行",
      service_brand: "アポ匠",
      service_path:  "/app",
      target: "新規商談獲得を外注したいBtoB企業の責任者",
      categories: ["課題解決", "選定・比較", "業界理解", "活用イメージ", "不安解消"],
      exclude: "成果報酬型営業の訴求"
    },
    ai: {
      service_name:  "AI活用型ブログ・SEO支援",
      service_brand: "AI生成BLOG",
      service_path:  "/ai",
      target: "SEO集客を効率化・内製化したい企業",
      categories: ["課題解決", "導入検討", "業界理解", "活用イメージ", "不安解消"],
      exclude: "個人ブロガー向けの発信"
    },
    construction: {
      service_name:  "建設現場労務支援サービス",
      service_brand: "OK建設",
      service_path:  "/construction",
      target: "建設現場の人手不足に悩む元請・施工会社",
      categories: ["課題解決", "選定・比較", "業界理解", "活用イメージ", "不安解消"],
      exclude: "作業員の求人を目的とした発信"
    }
  }.freeze

  def self.generate_columns(genre: nil, batch_count: 10)
    success_count = 0
    genre_list = genre ? [genre.to_sym] : GENRE_CONFIG.keys.shuffle
    processed = 0

    while processed < batch_count
      genre_list.each do |g|
        break if processed >= batch_count
        target_category = GENRE_CONFIG[g][:categories].sample
        success_count += 1 if execute_generation(g, target_category)
        processed += 1
        sleep 3 # API負荷軽減
      end
      genre_list.shuffle!
    end

    puts "\n✅ 完了: #{success_count} / #{batch_count} 件の記事を保存しました。"
    success_count
  end

  def self.execute_generation(original_genre, target_category)
    puts "\n--- [#{original_genre}] 生成開始 カテゴリ: #{target_category} ---"

    pillar = PillarSelector.select_available_pillar(original_genre)
    if pillar.nil?
      puts "❌ 親記事が見つかりません"
      return false
    end

    actual_genre = pillar.genre.to_sym
    config = GENRE_CONFIG[actual_genre]

    # プロンプトの改善：単一オブジェクトを強く要求
    prompt = <<~PROMPT
      以下の設定に基づき、ウェブ記事のメタ情報を「1つのJSONオブジェクト」として作成してください。
      絶対に複数の記事を作成しないでください。配列（[]）も使わないでください。

      【設定】
      サービス名: #{config[:service_name]} (#{config[:service_brand]})
      ターゲット: #{config[:target]}
      カテゴリー: #{target_category}
      除外対象: #{config[:exclude]}

      【出力JSON形式（必ず1つだけ）】
      {
        "title": "読者の課題を解決するタイトル",
        "code": "url-slug-text",
        "description": "120文字程度の要約",
        "keyword": "キーワード1, キーワード2"
      }
    PROMPT

    retries = 0
    loop do
      response_text = post_to_gemini(prompt)
      return false if response_text.nil?

      # JSON部分の抽出ロジックの改善
      # 配列 [] で返ってきた場合も考慮
      json_match = response_text.match(/(\{.*\}|\[.*\])/m)
      json_text = json_match ? json_match[0] : nil

      if json_text.nil?
        puts "❌ JSON抽出失敗"
        retries += 1
        break if retries >= MAX_RETRIES
        next
      end

      begin
        parsed_data = JSON.parse(json_text)
        
        # 配列で返ってきた場合は最初の1件を取得
        data = parsed_data.is_a?(Array) ? parsed_data.first : parsed_data

        required_keys = %w[title code description keyword]
        missing = required_keys.select { |k| data[k].to_s.strip.empty? }

        if missing.empty?
          Column.create!(
            title:       data["title"],
            code:        data["code"],
            description: data["description"],
            keyword:     data["keyword"],
            choice:      target_category,
            genre:       actual_genre.to_s,
            status:      "draft",
            article_type: "cluster",
            parent_id:   pillar.id
          )
          puts "✅ 保存成功: #{data["title"]}"
          return true
        else
          puts "❌ キー欠損: #{missing}"
        end
      rescue JSON::ParserError => e
        puts "❌ JSONパースエラー: #{e.message}"
        # パースに失敗した生データを少し表示してデバッグしやすくする
        puts "【問題のデータ冒頭】: #{json_text[0..100]}..." 
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
    
    # response_mime_type を指定することで、Geminiが文章を混ぜるのを防ぐ
    req.body = {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        response_mime_type: "application/json"
      }
    }.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    return nil unless res.is_a?(Net::HTTPSuccess)
    
    body = JSON.parse(res.body)
    body.dig("candidates", 0, "content", "parts", 0, "text")
  rescue => e
    puts "❌ API通信エラー: #{e.message}"
    nil
  end
end