class GeminiColumnGenerator
  require "net/http"
  require "json"
  require "openssl"

  GEMINI_API_KEY = ENV["GEMINI_API_KEY"]
  # 最新のモデル名（gemini-1.5-flashなど）に合わせて調整してください
  GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent"
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

    if genre
      config = GENRE_CONFIG.fetch(genre.to_sym)
      categories = config[:categories]
      index = 0

      batch_count.times do |i|
        target_category = categories[index]
        index = (index + 1) % categories.size

        success_count += 1 if execute_generation(genre.to_sym, target_category)
        sleep 7 if i < batch_count - 1
      end
    else
      genre_list = GENRE_CONFIG.keys.shuffle
      processed = 0

      while processed < batch_count
        genre_list.each do |g|
          break if processed >= batch_count

          target_category = GENRE_CONFIG[g][:categories].sample
          success_count += 1 if execute_generation(g, target_category)
          processed += 1

          sleep 7 if processed < batch_count
        end
        genre_list.shuffle!
      end
    end

    success_count
  end

  def self.execute_generation(genre, target_category)
    config = GENRE_CONFIG.fetch(genre)
    puts "--- [#{genre}] 生成開始 カテゴリ: #{target_category} ---"

    prompt = <<~EOS
      #{config[:service_name]}に関する企業向けブログ記事を日本語で作成してください。
      ターゲット読者：#{config[:target]}
      記事カテゴリ：「#{target_category}」

      記事タイトルには必ず「#{config[:service_name]}」という文言を含めてください。

      記事の目的：
      ・#{config[:service_brand]}のサービス内容を自然に理解してもらう
      ・最終的に「問い合わせしてみよう」と思ってもらう

      重要な条件：
      ・#{config[:exclude]}ではありません
      ・売り込みすぎず、実務目線で分かりやすく
      ・記事の最後は「#{config[:service_brand]}（#{config[:service_path]}）では〜」で締める

      URL用コード（slug）生成のルール：
      ・記事内容を英語で簡潔に表すURL用の文字列（code）を生成してください。
      ・SEOを意識し、重要なキーワードを凝縮してください。
      ・「a」「the」「is」「of」などの機能語（Stop words）は除外してください。
      ・半角英小文字とハイフンのみを使用してください（アンダースコア禁止）。
      ・単語間はハイフン「-」で繋いでください。

      keyword条件：
      ・SEOキーワードを3〜5個
      ・カンマ区切りのみ（説明文禁止）

      【出力ルール】
      以下のJSONを完全にそのままの構造で出力してください。
      キーの省略・追加は禁止です。

      {
        "title": "記事タイトル",
        "code": "seo-friendly-english-slug",
        "description": "記事本文（800〜1200文字）",
        "keyword": "キーワード1,キーワード2,キーワード3"
      }
    EOS

    retries = 0
    loop do
      response_text = post_to_gemini(prompt)
      return false unless response_text

      json_text = response_text[/\{.*\}/m]
      next if json_text.nil?

      data = JSON.parse(json_text) rescue nil
      next if data.nil?

      required_keys = %w[title code description keyword]
      missing = required_keys.select { |k| data[k].blank? }

      if missing.empty?
        Column.create!(
          title:       data["title"],
          code:        data["code"].downcase.strip, # 小文字化と空白除去
          description: data["description"],
          keyword:     data["keyword"],
          choice:      target_category,
          genre:       genre.to_s,
          status:      "draft"
        )
        puts "成功: [#{genre}] #{data['title']} (URL: /columns/#{data['code']})"
        return true
      else
        retries += 1
        puts "不完全JSON #{retries}回目: missing=#{missing.join(', ')}"
        sleep 3
        break if retries >= MAX_RETRIES
      end
    end

    puts "生成失敗: 必須キーが揃わず"
    false
  end

  def self.post_to_gemini(prompt)
    uri = URI(GEMINI_API_URL)
    uri.query = URI.encode_www_form(key: GEMINI_API_KEY)

    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")
    req.body = {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        responseMimeType: "application/json"
      }
    }.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
      http.request(req)
    end

    return nil unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body).dig("candidates", 0, "content", "parts", 0, "text")
  rescue => e
    puts "通信エラー: #{e.message}"
    nil
  end
end