# app/services/gemini_column_generator.rb
class GeminiColumnGenerator
  require "net/http"
  require "json"
  require "openssl"

  GEMINI_API_KEY = ENV["GEMINI_API_KEY"]
  GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent"

  # ジャンル定義（★ここを追加・編集するだけで多角化可能）
  GENRE_CONFIG = {
    cargo: {
      service_name: "軽貨物配送サービス",
      target: "軽貨物事業者との取引や協業を検討している企業の担当者または経営層（荷主企業やITベンダーなど）",
      categories: [
        "軽貨物パートナー選定",
        "物流DX・技術連携",
        "発注リスクと法令遵守",
        "市場トレンドと展望",
        "コスト最適化・事例"
      ],
      exclude: "求職者および軽貨物事業者自身に向けた発信"
    },

    security: {
      service_name: "警備業務（警備第一号）",
      target: "警備業務の外注や切替を検討している企業・施設管理者",
      categories: [
        "警備会社の選定基準",
        "警備業法とリスク管理",
        "施設・イベント警備",
        "コストと品質の最適化",
        "警備業界の市場動向"
      ],
      exclude: "警備員の求人や資格取得を目的とした発信"
    },

    cleaning: {
      service_name: "清掃業務",
      target: "清掃業務の外注を検討している法人・施設管理者",
      categories: [
        "清掃業者の選び方",
        "清掃品質と管理体制",
        "定期清掃とスポット清掃",
        "コスト最適化",
        "衛生・法令対応"
      ],
      exclude: "清掃スタッフの求人向け発信"
    },

    sales_agency: {
      service_name: "テレアポ型営業代行（商談提供型）",
      target: "新規商談獲得を外注したいBtoB企業の責任者",
      categories: [
        "営業代行の選定基準",
        "テレアポ外注のリスク",
        "商談提供型営業のメリット",
        "内製営業との比較",
        "営業代行市場の動向"
      ],
      exclude: "成約保証型・成果報酬型営業の訴求"
    },

    ai_blog: {
      service_name: "AI活用型ブログ・SEO支援",
      target: "SEO集客を効率化・内製化したい企業",
      categories: [
        "AI×SEOの活用方法",
        "ブログ運用の効率化",
        "SEO内製と外注の違い",
        "コンテンツ品質管理",
        "SEO市場の動向"
      ],
      exclude: "個人ブロガー向けの発信"
    },

    construction: {
      service_name: "建設現場労務支援サービス",
      target: "建設現場の人手不足に悩む元請・施工会社",
      categories: [
        "現場人材の確保方法",
        "外注時のリスク管理",
        "法令・安全管理",
        "コストと稼働最適化",
        "建設業界の動向"
      ],
      exclude: "作業員の求人を目的とした発信"
    }
  }.freeze

  def self.generate_columns(genre: :cargo, batch_count: 100)
    config = GENRE_CONFIG.fetch(genre)
    category_list = config[:categories]

    max_retries = 3
    current_category_index = 0

    batch_count.times do
      target_category = category_list[current_category_index]
      current_category_index = (current_category_index + 1) % category_list.size

      prompt = <<~EOS
        #{config[:service_name]}に関するブログ記事のテーマ、記事概要、SEOキーワード、およびカテゴリを日本語で生成してください。

        ターゲット読者は **#{config[:target]}** です。

        【最重要指示1：強制カテゴリ】
        必ずカテゴリ「#{target_category}」に属するテーマを生成してください。

        【最重要指示2：難易度】
        業界の専門家以外でも理解でき、実務に役立つ内容に限定し、
        専門的すぎる議論や学術的な話題は避けてください。

        【最重要指示3：目的】
        サービス導入・外注・提携の意思決定に役立つ情報を提供してください。

        #{config[:exclude]}ではありません。

        カテゴリは以下から必ず1つ選択してください:
        #{category_list.join(", ")}
      EOS

      response_json_string = nil

      max_retries.times do |attempt|
        response_json_string = post_to_gemini(prompt, category_list)
        break if response_json_string

        if attempt < max_retries - 1
          sleep_time = 2 ** attempt
          Rails.logger.warn("Gemini API失敗 (#{attempt + 1}/#{max_retries})。#{sleep_time}秒後に再試行")
          sleep(sleep_time)
        end
      end

      next unless response_json_string

      begin
        data = JSON.parse(response_json_string)

        Column.create!(
          title:       data["title"],
          description: data["description"],
          keyword:     data["keyword"],
          choice:      data["category"],
          genre:       genre.to_s,
          status:      "draft"
        )
      rescue JSON::ParserError => e
        Rails.logger.error("JSONパースエラー: #{e.message} - #{response_json_string}")
      rescue => e
        Rails.logger.error("DB保存エラー: #{e.message}")
      end
    end
  end

  def self.post_to_gemini(prompt, category_list = nil)
    uri = URI(GEMINI_API_URL)
    uri.query = URI.encode_www_form(key: GEMINI_API_KEY)

    req = Net::HTTP::Post.new(uri, "Content-Type" => "application/json")

    category_schema = { "type": "string" }
    category_schema["enum"] = category_list if category_list.present?

    req.body = {
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: {
          type: "object",
          properties: {
            title:       { type: "string" },
            description: { type: "string" },
            keyword:     { type: "string" },
            category:    category_schema
          },
          required: %w[title description keyword category]
        }
      }
    }.to_json

    res = Net::HTTP.start(
      uri.hostname,
      uri.port,
      use_ssl: true,
      verify_mode: OpenSSL::SSL::VERIFY_NONE,
      read_timeout: 120
    ) { |http| http.request(req) }

    return nil unless res.is_a?(Net::HTTPSuccess)

    api_response = JSON.parse(res.body)
    api_response.dig("candidates", 0, "content", "parts", 0, "text")
  end
end
