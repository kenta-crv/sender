require 'net/http'
require 'json'
require 'uri'
require 'socket'

# 試験発信の前に、公開URLが本当につながるかを確かめる。
class TwilioPublicUrl
  NGROK_API = 'http://127.0.0.1:4040/api/tunnels'.freeze

  def self.ensure_ready!
    tunnel = local_tunnel
    if tunnel.nil?
      raise '公開用の接続が切れているため発信できません。ngrok を起動してください。'
    end

    public_url = tunnel[:public_url]
    local_url = tunnel[:local_url]
    ENV['NGROK_URL'] = public_url
    write_dotenv_ngrok!(public_url)

    # 画面の処理から同じ rails s へ HTTP を投げると、その場で止まる。
    unless port_open?(local_url)
      raise 'アプリ側の受け口が応答していません。rails s が 3000 番で起動しているか確認してください。'
    end

    public_url
  end

  def self.ready?
    ensure_ready!
    true
  rescue StandardError => e
    Rails.logger.warn("[TwilioPublicUrl] not ready: #{e.message}")
    false
  end

  def self.ready_message
    ensure_ready!
    '公開接続は通っています。'
  rescue StandardError => e
    e.message
  end

  def self.local_tunnel
    uri = URI(NGROK_API)
    res = Net::HTTP.start(uri.host, uri.port, open_timeout: 1, read_timeout: 2) do |http|
      http.get(uri.request_uri)
    end
    return nil unless res.is_a?(Net::HTTPSuccess)

    data = JSON.parse(res.body)
    https = Array(data['tunnels']).find { |t| t['public_url'].to_s.start_with?('https://') }
    return nil if https.blank?

    public_url = https['public_url'].to_s.sub(%r{/+\z}, '')
    addr = https.dig('config', 'addr').to_s
    addr = "http://127.0.0.1:3000" if addr.blank?
    addr = addr.sub(%r{\Ahttp://localhost\b}, 'http://127.0.0.1')
    addr = addr.sub(%r{\Ahttps://localhost\b}, 'http://127.0.0.1')
    {
      public_url: public_url,
      local_url: addr
    }
  rescue StandardError
    nil
  end

  def self.port_open?(url)
    uri = URI(url)
    host = uri.host
    host = '127.0.0.1' if host == 'localhost'
    Socket.tcp(host, uri.port, connect_timeout: 1) { true }
  rescue StandardError
    false
  end

  def self.write_dotenv_ngrok!(public_url)
    path = Rails.root.join('.env')
    return unless File.exist?(path)

    current = File.read(path)
    return if current.match?(/^NGROK_URL=#{Regexp.escape(public_url)}$/)

    lines = current.lines
    replaced = false
    lines.map! do |line|
      if line.start_with?('NGROK_URL=')
        replaced = true
        "NGROK_URL=#{public_url}\n"
      else
        line
      end
    end
    lines << "NGROK_URL=#{public_url}\n" unless replaced
    File.write(path, lines.join)
  rescue StandardError => e
    Rails.logger.warn("[TwilioPublicUrl] .env更新に失敗: #{e.message}")
  end
  private_class_method :write_dotenv_ngrok!, :local_tunnel, :port_open?
end
