require "net/http"
require "json"
require "openssl"
require "openai"

class GptPillarGenerator
  MODEL_NAME = "gpt-4o-mini"

  TARGET_CHARS_PER_H2 = 1000
  MAX_CHARS_PER_H2 = 1400

  GPT_API_KEY = ENV["OPENAI_API_KEY"]
  GPT_API_URL = "https://api.openai.com/v1/chat/completions"

  CATEGORY_KEYWORDS = {
    "警備"     => ["警備"],
    "軽貨物"   => ["軽貨物", "配送"],
    "清掃"     => ["清掃"],
    "営業代行" => ["営業代行", "テレアポ"],
    "ブログ"   => ["ブログ"],
    "建設"     => ["建設", "現場"]
  }

  def self.generate_body(column, child_columns: [])
    return nil unless GPT_API_KEY.present?

    category = detect_category(column.keyword)

    structure_prompt = pillar_structure_prompt(column, category, child_columns)
    structure_response = call_gpt_api(structure_prompt, response_format: { type: "json_object" })

    return column.body if structure_response.nil?

    json_str = structure_response.dig("choices", 0, "message", "content")
    structure_data = JSON.parse(json_str)
    structure = structure_data["structure"]

    article = ""

    # 1. 導入文
    article += call_section(introduction_prompt(column, category)) + "\n\n"

    # 2. 各H2セクションの生成
    structure.each do |section|
      # プログラム側で見出しを付与
      article += "## #{section["h2_title"]}\n\n"
      # GPT側には本文のみを書かせる（見出しの重複防止）
      article += call_section(h2_content_prompt(column, category, section, child_columns)) + "\n\n"
      sleep(0.5)
    end

    # 3. まとめ
    article += call_section(conclusion_prompt(column, category))

    # =====================================================================
    # 【最重要】既存の正規表現 /<(h[2-4])>/ にマッチさせるための処理
    # KramdownがHTML変換時に見出しに自動で id 属性を付与するのを停止させます。
    # これによりタグが <h2> になり、Controllerを変更せずとも抽出可能になります。
    # =====================================================================
    article + "\n\n{::options auto_ids=\"false\" /}"
  end

  def self.detect_category(keyword)
    return "その他" if keyword.blank?

    CATEGORY_KEYWORDS.each do |category, words|
      return category if words.any? { |w| keyword.include?(w) }
    end

    "その他"
  end

  # ==============================
  # プロンプト群
  # ==============================

  def self.pillar_structure_prompt(column, category, child_columns)
    child_titles = child_columns.map(&:title).join("\n- ")

    <<~PROMPT
      あなたはSEOに強い編集長レベルの専門ライターです。

      # 記事情報
      - タイトル: #{column.title}
      - 概要: #{column.description}
      - キーワード: #{column.keyword}
      - 業種: #{category}
      - 役割: 業界全体を網羅する「ピラー記事」

      # 子記事一覧
      - #{child_titles.presence || "なし"}

      # 指示
      - 業界全体を体系的に理解できる構成にする
      - H2は6〜9個
      - 各H2は独立して1,000文字以上書けるテーマにする
      - 導入・まとめは含めない

      # 出力形式（JSONのみ）
      {
        "structure": [
          { "h2_title": "見出し" }
        ]
      }
    PROMPT
  end

  def self.introduction_prompt(column, category)
    <<~PROMPT
      タイトル「#{column.title}」の記事の導入文を書いてください。
      - 業種: #{category}
      - 文字数: 600〜800文字
      - 見出しは含めない
      - 読者の悩みに共感 → メリット提示 → 全体像の予告
    PROMPT
  end

  def self.h2_content_prompt(column, category, section, child_columns)
    child_titles = child_columns.map(&:title).join("、")

    <<~PROMPT
      以下のH2セクションの【本文のみ】を書いてください。

      - 記事タイトル: #{column.title}
      - H2見出し: #{section["h2_title"]}

      # 【厳守】禁止事項
      - 見出し（## や <h2>）を絶対に本文内に書かないでください。
      - 書き出しに見出しを繰り返さないでください。

      # 要件
      - 専門家レベルの深さで解説する
      - 必要に応じてH3（###）や箇条書きを活用
      - 子記事「#{child_titles.presence || "該当なし"}」への誘導を自然に含める
      - 文字数: 800〜1,200文字程度
      - です・ます調
    PROMPT
  end

  def self.conclusion_prompt(column, category)
    <<~PROMPT
      記事全体のまとめを書いてください。
      - 【重要】必ず「## まとめ」という文字列から開始してください。
      - 記事全体を体系的に要約。
      - 400〜600文字程度。
    PROMPT
  end

  # ==============================
  # GPT実行
  # ==============================

  def self.call_section(prompt)
    response = call_gpt_api(prompt)
    response&.dig("choices", 0, "message", "content") || "（生成失敗）"
  end

  def self.call_gpt_api(prompt, response_format: nil)
    uri = URI(GPT_API_URL)

    req = Net::HTTP::Post.new(uri, {
      "Content-Type" => "application/json",
      "Authorization" => "Bearer #{GPT_API_KEY}"
    })

    payload = {
      model: MODEL_NAME,
      messages: [
        { role: "system", content: "あなたはSEO戦略に精通した編集長クラスの専門ライターです。" },
        { role: "user", content: prompt }
      ],
      temperature: 0.4
    }

    payload[:response_format] = response_format if response_format.present?
    req.body = payload.to_json

    res = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, read_timeout: 150) do |http|
      http.request(req)
    end

    res.is_a?(Net::HTTPSuccess) ? JSON.parse(res.body) : nil
  end
end