class TwilioService
  def initialize
    @client = Twilio::REST::Client.new(
      ENV.fetch('TWILIO_ACCOUNT_SID'),
      ENV.fetch('TWILIO_AUTH_TOKEN')
    )
  end

  # 日本の電話番号をE.164形式に変換（例: "03-6820-3278" → "+81368203278"）
  def self.public_base_url
    refresh_public_url_from_dotenv
    url = ENV['NGROK_URL'].presence || ENV['APP_BASE_URL'].presence
    url.to_s.sub(/\/+\z/, '')
  end

  def self.refresh_public_url_from_dotenv
    path = Rails.root.join('.env')
    return unless File.exist?(path)

    File.foreach(path) do |line|
      line = line.strip
      next if line.empty? || line.start_with?('#')

      key, value = line.split('=', 2)
      next unless %w[NGROK_URL APP_BASE_URL].include?(key)

      ENV[key] = value.to_s.strip.gsub(/\A["']|["']\z/, '')
    end
  end

  def self.to_e164(tel)
    return tel if tel.nil? || tel.empty?
    return tel if tel.start_with?('+')

    digits = tel.gsub(/[^\d]/, '')
    if digits.start_with?('0')
      "+81#{digits[1..]}"
    else
      "+81#{digits}"
    end
  end

  # 顧客に発信
  def initiate_call(customer, call, base_url)
    twilio_call = @client.calls.create(
      to: self.class.to_e164(customer.tel),
      from: config.from_number,
      url: "#{base_url}/twilio/voice?call_id=#{call.id}",
      status_callback: "#{base_url}/twilio/status",
      status_callback_event: %w[initiated ringing answered completed],
      timeout: (config.no_answer_timeout.presence || 10).to_i,
      record: true,
      recording_status_callback: "#{base_url}/twilio/recording_status",
      recording_status_callback_method: 'POST'
    )
    twilio_call.sid
  end

  def hangup_call(call_sid)
    return if call_sid.blank?

    @client.calls(call_sid).update(status: 'completed')
  rescue => e
    Rails.logger.error("[TwilioService] 通話停止エラー: #{e.message}")
  end

  SCRIPT_KEYS = DialScript::SCRIPT_KEYS
  HANGUP_SCRIPTS = Call.StatuItems

  def self.hangup_script?(script)
    HANGUP_SCRIPTS.include?(script.to_s)
  end

  def self.purpose_played?(call)
    call&.speech_result.to_s.include?('[purpose]')
  end

  def self.script_text(key, call = nil)
    from_pack = call.is_a?(Call) ? call.dial_script&.text_for(key) : nil
    return from_pack if from_pack.present?

    case key.to_s
    when 'greeting'
      'お電話ありがとうございます。'
    when 'purpose'
      '本日はご案内でお電話しました。続きをお聞きいただけますか。'
    when 'wait'
      '承知しました。そのままお待ちします。'
    when 'repeat'
      DialScript::REPEAT_TEXT
    else
      ''
    end
  end

  # 登録した語句に合う文章だけを選ぶ。文章は作らない。一致が無ければ聞き直す。
  def self.choose_script(text, call: nil, purpose_played: nil)
    text = utf8_speech(text)
    return 'repeat' if text.blank?

    pack = call.is_a?(Call) ? call.dial_script : nil
    saved = match_saved_utterance(text, pack)
    return saved if DialScript::SCRIPT_KEYS.include?(saved.to_s)

    'repeat'
  end

  def self.utf8_speech(text)
    return '' if text.nil?

    unless text.encoding == Encoding::UTF_8
      text = text.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
    end
    text.to_s.strip
  end

  def self.match_saved_utterance(text, pack)
    return nil unless pack

    pack.dial_utterances.select { |u| u.phrase.present? }.sort_by { |u| -u.phrase.size }.each do |utterance|
      return utterance.script_key if text.include?(utterance.phrase)
    end
    nil
  end

  # 録音を削除
  def delete_recording(recording_sid)
    @client.recordings(recording_sid).delete
  rescue => e
    Rails.logger.error("[TwilioService] 録音削除エラー: #{e.message}")
  end

  private

  def config
    @config ||= TwilioConfig.current
  end
end
