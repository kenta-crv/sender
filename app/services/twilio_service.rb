class TwilioService
  def initialize
    @client = Twilio::REST::Client.new(
      ENV.fetch('TWILIO_ACCOUNT_SID'),
      ENV.fetch('TWILIO_AUTH_TOKEN')
    )
  end

  # 日本の電話番号をE.164形式に変換（例: "03-6820-3278" → "+81368203278"）
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
      timeout: config.no_answer_timeout
    )
    twilio_call.sid
  end

  # オペレーターをConferenceに呼び出し
  def call_operator_to_conference(conference_name, base_url)
    @client.calls.create(
      to: config.operator_number,
      from: config.from_number,
      url: "#{base_url}/twilio/operator_join?conference=#{conference_name}",
      status_callback: "#{base_url}/twilio/status",
      status_callback_event: %w[initiated ringing answered completed]
    )
  end

  SCRIPT_KEYS = %w[greeting purpose wait absent rejection no_human repeat closing].freeze
  HANGUP_SCRIPTS = %w[absent rejection no_human closing].freeze

  def self.hangup_script?(script)
    HANGUP_SCRIPTS.include?(script.to_s)
  end

  def self.purpose_played?(call)
    call&.speech_result.to_s.include?('[purpose]')
  end

  def self.script_text(key, config = TwilioConfig.current)
    from_pack = DialScript.current&.text_for(key)
    return from_pack if from_pack.present?

    case key.to_s
    when 'greeting'
      'お電話ありがとうございます。こちらはAIによる自動案内です。株式会社テストでございます。本日はサービスのご案内でお電話しました。今、お話できますでしょうか。'
    when 'purpose'
      config.inquiry_text.presence || '本日は、業務のご案内でお電話しました。この場で契約や資料送付のお約束はできません。続きをお聞きいただけますか。'
    when 'wait'
      '承知しました。そのままお待ちします。'
    when 'absent'
      config.absent_text.presence || '承知いたしました。改めてお電話させていただきます。失礼いたします。'
    when 'rejection'
      config.rejection_text.presence || '承知いたしました。お時間いただきありがとうございました。失礼いたします。'
    when 'no_human'
      '恐れ入ります。この電話はAIの自動案内のみで、人へのおつなぎはしておりません。ご案内は以上です。失礼いたします。'
    when 'repeat'
      '恐れ入ります。もう一度お願いできますか。'
    when 'closing'
      'ご案内は以上です。お電話ありがとうございました。失礼いたします。'
    else
      script_text('repeat', config)
    end
  end

  # 返す文は原稿のみ。ここでは原稿番号だけ決める。黙らない。
  def self.choose_script(text, purpose_played: false)
    text = utf8_speech(text)
    return 'repeat' if text.blank?

    picked = choose_script_by_model(text, purpose_played: purpose_played)
    picked = choose_script_fallback(text, purpose_played: purpose_played) unless SCRIPT_KEYS.include?(picked)
    picked = 'repeat' unless SCRIPT_KEYS.include?(picked)
    picked
  end

  def self.utf8_speech(text)
    return '' if text.nil?

    unless text.encoding == Encoding::UTF_8
      text = text.encode('UTF-8', invalid: :replace, undef: :replace, replace: '')
    end
    text.to_s.strip
  end

  def self.choose_script_by_model(text, purpose_played:)
    api_key = ENV['OPENAI_API_KEY'].presence || ENV['GPT_API_KEY'].presence
    return nil if api_key.blank?

    client = OpenAI::Client.new(access_token: api_key)
    response = client.chat(
      parameters: {
        model: 'gpt-4.1-mini',
        temperature: 0,
        max_tokens: 40,
        messages: [
          {
            role: 'system',
            content: '電話の相手の発話から、次に流す原稿のキーだけをJSONで返す。文は作らない。キーは purpose, wait, absent, rejection, no_human, repeat, closing のいずれか。{"script":"purpose"} のみ。人へつなぐ原稿は無い。purpose_playedがtrueなら用件は既に話した。'
          },
          {
            role: 'user',
            content: "purpose_played=#{purpose_played}\n発話: #{text}"
          }
        ]
      }
    )
    raw = response.dig('choices', 0, 'message', 'content').to_s
    json = JSON.parse(raw[/{.*}/m].to_s)
    json['script'].to_s
  rescue => e
    Rails.logger.warn("[TwilioService] choose_script_by_model: #{e.message}")
    nil
  end

  def self.match_saved_utterance(text)
    pack = DialScript.current
    return nil unless pack

    pack.dial_utterances.select { |u| u.phrase.present? }.sort_by { |u| -u.phrase.size }.each do |utterance|
      return utterance.script_key if text.include?(utterance.phrase)
    end
    nil
  end

  def self.choose_script_fallback(text, purpose_played:)
    return 'repeat' if text.size < 2

    saved = match_saved_utterance(text)
    return saved if SCRIPT_KEYS.include?(saved.to_s)

    if text.match?(/人に|担当.*出|代わってください|オペレーター|オペレータ/)
      'no_human'
    elsif text.match?(/不在|外出|席を外|おりません|いません|留守|出かけ/)
      'absent'
    elsif text.match?(/結構です|必要ありません|間に合|いらない|お断り|結構/)
      'rejection'
    elsif text.match?(/少々|お待ち|待って|保留/)
      'wait'
    elsif purpose_played && text.match?(/はい|ええ|わかりました|分かりました|了解|ありがとう/)
      'closing'
    elsif !purpose_played && text.match?(/はい|ええ|どうぞ|お願いします|何ですか|ご用件|もしもし/)
      'purpose'
    elsif purpose_played
      'repeat'
    else
      'purpose'
    end
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
