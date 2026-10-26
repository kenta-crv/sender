require 'net/http'
require 'json'
require 'uri'

# OpenAI Chat / Embeddings。古い openai gem には chat が無いため HTTP 直叩き。
class DialLlmClient
  API_BASE = 'https://api.openai.com/v1'.freeze
  CHAT_MODEL = ENV.fetch('DIAL_LLM_MODEL', 'gpt-4.1-mini').freeze
  EMBED_MODEL = ENV.fetch('DIAL_EMBED_MODEL', 'text-embedding-3-small').freeze

  def self.enabled?
    api_key.present?
  end

  def self.api_key
    ENV['OPENAI_API_KEY'].presence || ENV['OPENAI_ACCESS_TOKEN'].presence || ENV['GPT_API_KEY'].presence
  end

  def self.chat_json(system:, user:, temperature: 0.1, read_timeout: 20, open_timeout: 5)
    return nil unless enabled?

    body = {
      model: CHAT_MODEL,
      temperature: temperature,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: system },
        { role: 'user', content: user }
      ]
    }
    data = post_json('/chat/completions', body, read_timeout: read_timeout, open_timeout: open_timeout)
    content = data.dig('choices', 0, 'message', 'content')
    return nil if content.blank?

    JSON.parse(content)
  rescue => e
    Rails.logger.error("[DialLlmClient] chat_json error: #{e.message}")
    nil
  end

  def self.embed(text)
    return nil unless enabled?
    return nil if text.blank?

    body = {
      model: EMBED_MODEL,
      input: text.to_s
    }
    data = post_json('/embeddings', body)
    data.dig('data', 0, 'embedding')
  rescue => e
    Rails.logger.error("[DialLlmClient] embed error: #{e.message}")
    nil
  end

  def self.cosine(a, b)
    return 0.0 if a.blank? || b.blank? || a.size != b.size

    dot = 0.0
    na = 0.0
    nb = 0.0
    a.each_with_index do |v, i|
      x = v.to_f
      y = b[i].to_f
      dot += x * y
      na += x * x
      nb += y * y
    end
    return 0.0 if na <= 0.0 || nb <= 0.0

    dot / Math.sqrt(na * nb)
  end

  def self.post_json(path, body, read_timeout: 20, open_timeout: 5)
    uri = URI.parse("#{API_BASE}#{path}")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    http.open_timeout = open_timeout
    http.read_timeout = read_timeout
    req = Net::HTTP::Post.new(uri)
    req['Authorization'] = "Bearer #{api_key}"
    req['Content-Type'] = 'application/json'
    req.body = JSON.generate(body)
    res = http.request(req)
    raise "HTTP #{res.code}: #{res.body.to_s.truncate(200)}" unless res.is_a?(Net::HTTPSuccess)

    JSON.parse(res.body)
  end
  private_class_method :post_json
end
