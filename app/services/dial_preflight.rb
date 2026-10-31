require 'net/http'
require 'google/cloud/speech/v1'
require 'uri'

# 発信の前に、電話が成り立つのに必要なものを全部確かめる。
# 1つでも駄目なら発信しない（壊れた状態で相手につながるのを防ぐ）。
#
#   ターミナルから: ruby bin/rails runner 'puts DialPreflight.report'
#   試験発信の前:   DialPreflight.run(public_ping: false)  ※画面の処理中は自分自身へ HTTP を投げると止まるため
class DialPreflight
  Check = Struct.new(:name, :ok, :detail, :fix, keyword_init: true)

  # 通話で必ず流す可能性がある録音
  REQUIRED_RECORDINGS = %w[
    greeting wait clarify clarify_simple silence_1 silence_2 callback purpose transfer
    着信不在 フロントアウト 担当者不在
  ].freeze
  # 音声認識の確認に使う録音（「お電話が少し遠いようでして…」）
  STT_SAMPLE_KEY = 'silence_2'.freeze

  # 発信ボタンのたびに外部へ問い合わせると数秒待たされるため、
  # 全部 OK だった結果は CACHE_SEC 秒だけ使い回す（NG は使い回さない）
  CACHE_SEC = 600

  def self.run(public_ping: true, script: nil, cache: false)
    if cache && @ok_at && Process.clock_gettime(Process::CLOCK_MONOTONIC) - @ok_at < CACHE_SEC
      return @ok_checks
    end

    checks = new(public_ping: public_ping, script: script).run
    if checks.all?(&:ok)
      @ok_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      @ok_checks = checks
    else
      @ok_at = nil
    end
    checks
  end

  def self.report(public_ping: true)
    checks = run(public_ping: public_ping)
    lines = ['===== 発信前の点検 =====']
    checks.each do |c|
      lines << "#{c.ok ? 'OK' : 'NG'}  #{c.name}  #{c.detail}"
      lines << "    → #{c.fix}" if !c.ok && c.fix.present?
    end
    ng = checks.count { |c| !c.ok }
    lines << ''
    lines << (ng.zero? ? '結果: すべてOK。試験発信できます。' : "結果: NG #{ng} 件。上の → の対処をしてから、もう一度点検してください。")
    lines.join("\n")
  end

  def self.failure_message(checks)
    bad = checks.reject(&:ok)
    return nil if bad.empty?

    "発信前の点検で止めました（電話はかけていません）: " +
      bad.map { |c| "#{c.name}: #{c.detail}#{c.fix.present? ? "（#{c.fix}）" : ''}" }.join(' / ')
  end

  def initialize(public_ping:, script:)
    @public_ping = public_ping
    @script = script || DialScript.find_by(id: 1)
  end

  # 外部サービスへの問い合わせは同時に行う（順番に待つと合計で数秒かかる）
  def run
    checks = [check_script, check_recordings]
    @from_number = TwilioConfig.current.from_number.to_s # DB はここで読み、別スレッドでは触らない
    [DialLlmClient, TwilioPublicUrl] # 別スレッドでの読み込み待ちを避ける
    jobs = %i[check_twilio check_google check_llm check_public_url].map do |name|
      Thread.new { send(name) }
    end
    if defined?(ActiveSupport::Dependencies) && ActiveSupport::Dependencies.respond_to?(:interlock)
      ActiveSupport::Dependencies.interlock.permit_concurrent_loads { jobs.each(&:join) }
    else
      jobs.each(&:join)
    end
    checks + jobs.map(&:value)
  end

  private

  # fix は文字列か、失敗内容を受け取って対処を返す Proc
  def guard(name, fix)
    ok, detail = yield
    Check.new(name: name, ok: ok, detail: detail.to_s, fix: ok ? nil : fix_for(fix, detail.to_s))
  rescue StandardError => e
    message = e.message.to_s.gsub(/\s+/, ' ').strip
    Check.new(name: name, ok: false, detail: "#{e.class}: #{message[0, 160]}", fix: fix_for(fix, message))
  end

  def fix_for(fix, message)
    fix.respond_to?(:call) ? fix.call(message) : fix
  end

  def google_fix(message)
    project = message[/project[ #]+([\w-]+)/i, 1]
    if message.match?(/billing/i)
      "Google Cloud で課金を有効にしてください: https://console.cloud.google.com/billing/linkedaccount?project=#{project}"
    elsif message.match?(/SERVICE_DISABLED|has not been used|is disabled/i)
      "音声認識の API を有効にしてください: gcloud services enable speech.googleapis.com --project=#{project}"
    elsif message.match?(/鍵ファイルがありません/)
      '.env の GOOGLE_APPLICATION_CREDENTIALS の行を消すか、正しい鍵ファイルにしてください'
    else
      'ターミナルで gcloud auth application-default login を実行し、Google アカウントでログインし直してください'
    end
  end

  def check_script
    guard('原稿', '原稿 ID 1 を作成してください') do
      @script ? [true, "ID #{@script.id}: #{@script.name}"] : [false, '原稿 ID 1 がありません']
    end
  end

  def check_recordings
    guard('録音（音声ファイル）', 'ターミナルで ruby bin/rails runner \'DialPlaybackCache.preload!(DialScript.find(1))\' を実行し、エラー内容を確認してください') do
      next [false, '原稿がないため確認できません'] unless @script

      DialPlaybackCache.preload!(@script)
      missing = REQUIRED_RECORDINGS.reject do |key|
        bytes = DialPlaybackCache.fetch(@script.id, key)
        bytes && bytes.bytesize > 160
      end
      missing.empty? ? [true, "#{REQUIRED_RECORDINGS.size} 種類そろっています"] : [false, "足りない録音: #{missing.join('、')}"]
    end
  end

  def check_twilio
    guard('Twilio（電話回線）', 'Twilio の管理画面で、アカウントの状態と残高を確認してください') do
      sid = ENV['TWILIO_ACCOUNT_SID'].to_s
      token = ENV['TWILIO_AUTH_TOKEN'].to_s
      next [false, '.env の TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN が空です'] if sid.empty? || token.empty?

      client = Twilio::REST::Client.new(sid, token)
      account = client.api.v2010.accounts(sid).fetch
      next [false, "アカウントが有効ではありません（状態: #{account.status}）"] unless account.status.to_s == 'active'

      from = @from_number.to_s
      next [false, '発信元の電話番号（TWILIO_FROM_NUMBER）が空です'] if from.empty?

      detail = "アカウント有効 / 発信元 #{from}"
      begin
        bal = client.api.v2010.accounts(sid).balance.fetch
        detail += " / 残高 #{bal.balance} #{bal.currency}"
        next [false, "残高がありません（#{bal.balance} #{bal.currency}）"] if bal.balance.to_f <= 0
      rescue StandardError
        detail += ' / 残高は取得できませんでした'
      end
      [true, detail]
    end
  end

  def check_google
    guard('Google 音声認識（相手の声を文字にする）', method(:google_fix)) do
      # 鍵ファイルの指定がなければ、Mac でログインした Google アカウントの認証情報を使う
      path = ENV['GOOGLE_APPLICATION_CREDENTIALS'].to_s
      next [false, "鍵ファイルがありません: #{File.basename(path)}"] if path.present? && !File.exist?(path)
      next [false, '原稿がないため確認できません'] unless @script

      audio = DialPlaybackCache.fetch(@script.id, STT_SAMPLE_KEY)
      next [false, "確認用の録音（#{STT_SAMPLE_KEY}）がありません"] if audio.nil? || audio.bytesize < 1600

      client = Google::Cloud::Speech::V1::Speech::Client.new do |config|
        config.credentials = path if path.present?
        config.timeout = 10
      end
      config = Google::Cloud::Speech::V1::RecognitionConfig.new(
        encoding: Google::Cloud::Speech::V1::RecognitionConfig::AudioEncoding::MULAW,
        sample_rate_hertz: 8000,
        language_code: 'ja-JP',
        model: 'phone_call'
      )
      response = client.recognize(config: config, audio: { content: audio })
      text = Array(response.results).map { |r| r.alternatives.first&.transcript.to_s }.join
      via = path.present? ? "鍵ファイル #{File.basename(path)}" : 'Google アカウントのログイン'
      text.present? ? [true, "認識できました「#{text[0, 30]}」（#{via}）"] : [false, '音声を送りましたが文字が返りませんでした']
    end
  end

  def check_llm
    guard('AI 判定（OpenAI）', '.env の GPT_API_KEY と DIAL_LLM_MODEL（未設定なら gpt-4.1-mini）を確認してください') do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      # 一時的な通信の詰まりで止めないよう、1回だけやり直す
      model = begin
        DialLlmClient.ping!
      rescue Net::OpenTimeout, Net::ReadTimeout, Errno::ECONNRESET, SocketError
        sleep 1
        DialLlmClient.ping!(read_timeout: 8)
      end
      ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      [true, "#{model} が応答（#{ms}ミリ秒）"]
    end
  end

  def check_public_url
    guard('公開URL（Twilio からこのMacへの入口）', 'ngrok を起動し直し、./start_dev.sh check で確認してください') do
      base = TwilioPublicUrl.ensure_ready!
      next [true, "#{base}（画面からの点検のため外からの到達確認は省略）"] unless @public_ping

      uri = URI("#{base}/twilio/ping")
      res = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 5) do |http|
        req = Net::HTTP::Get.new(uri)
        req['ngrok-skip-browser-warning'] = '1'
        http.request(req)
      end
      ok = res.is_a?(Net::HTTPSuccess) && res.body.to_s.strip == 'ok'
      ok ? [true, "#{base} に外から届きます"] : [false, "#{base}/twilio/ping が #{res.code} を返しました"]
    end
  end
end
