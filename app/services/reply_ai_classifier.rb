require 'net/http'
require 'json'

# ルールで決まらなかったメールだけを OpenAI（既定 gpt-6-luna・推論なし）で分類する。
class ReplyAiClassifier
  MODEL = ENV.fetch('REPLY_LLM_MODEL', 'gpt-6-luna').freeze
  BODY_LIMIT = 1500 # AIに渡す本文の上限文字数（料金を抑えるため）

  SYSTEM = <<~PROMPT.freeze
    あなたはメールの仕分け係です。
    当社は企業のホームページの問い合わせフォームから営業の連絡を送っています。
    この受信箱には次のようなメールが届きます。
    - auto: フォーム送信直後に相手のシステムが自動で送る受付確認（「受け付けました」「確認メール」など）
    - human: 相手企業の担当者が、当社の連絡を読んで自分で書いた返信（興味、質問、断りなど）
    - other: メルマガ、セミナーや展示会の案内、広告、迷惑メール、詐欺メール、情報流出のお詫びなどの一斉通知、当社の連絡と無関係なもの
    humanの場合は intent を interest（興味・前向き）、question（質問）、decline（断り・不要）、none（どれでもない）から選びます。
    human以外の intent は none にします。
    次のJSONだけを返してください: {"category":"auto|human|other","intent":"interest|question|decline|none","reason":"20字以内の理由"}
  PROMPT

  def self.api_key
    ENV['OPENAI_API_KEY'].presence || ENV['OPENAI_ACCESS_TOKEN'].presence || ENV['GPT_API_KEY'].presence
  end

  def self.enabled?
    api_key.present?
  end

  # 戻り値: { category:, intent:, reason: } または nil（失敗時）
  def self.call(from:, subject:, body:, matched_send:)
    return nil unless enabled?

    user = <<~TEXT
      差出人: #{from}
      件名: #{subject}
      当社の送信先と同じドメインか: #{matched_send ? 'はい' : 'いいえ（不明）'}
      本文:
      #{body.to_s.gsub(/\n{3,}/, "\n\n").truncate(BODY_LIMIT)}
    TEXT

    uri = URI('https://api.openai.com/v1/chat/completions')
    req = Net::HTTP::Post.new(uri, 'Content-Type' => 'application/json',
                                   'Authorization' => "Bearer #{api_key}")
    req.body = {
      model: MODEL,
      reasoning_effort: 'none', # 考える処理を使わない（料金が増えず一定になる）
      max_completion_tokens: 100,
      response_format: { type: 'json_object' },
      messages: [{ role: 'system', content: SYSTEM }, { role: 'user', content: user }]
    }.to_json
    res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 20) { |h| h.request(req) }
    raise "HTTP #{res.code}: #{res.body.to_s[0, 200]}" unless res.is_a?(Net::HTTPSuccess)

    data = JSON.parse(JSON.parse(res.body).dig('choices', 0, 'message', 'content').to_s)
    category = data['category'].to_s
    return nil unless %w[auto human other].include?(category)

    intent = data['intent'].to_s
    intent = 'none' unless %w[interest question decline none].include?(intent)
    intent = 'none' unless category == 'human'
    { category: category, intent: intent, reason: data['reason'].to_s[0, 40] }
  rescue StandardError => e
    Rails.logger.error("[ReplyAiClassifier] #{e.class} #{e.message}")
    nil
  end
end
