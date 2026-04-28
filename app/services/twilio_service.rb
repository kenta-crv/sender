class TwilioService
  def initialize
    @client = Twilio::REST::Client.new(
      ENV.fetch('TWILIO_ACCOUNT_SID'),
      ENV.fetch('TWILIO_AUTH_TOKEN')
    )
  end

  # 日本式の電話番号(03-1234-5678)をE.164形式(+81312345678)に変換
  def self.to_e164(tel)
    return tel if tel.nil? || tel.empty?
    return tel if tel.start_with?('+')
    digits = tel.gsub(/[^0-9]/, '')
    if digits.start_with?('0')
      "+81#{digits[1..]}"
    else
      "+#{digits}"
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

  # 音声認識キーワード判定
  def self.classify_speech(text)
    return ["unknown", nil] if text.nil? || text.empty?

    text = text.encode('UTF-8', invalid: :replace, undef: :replace, replace: '') unless text.encoding == Encoding::UTF_8

    case text
    when /待たせ|担当|代わり|かわりました|分かりました|繋ぐ|つなぎ|変わり/
      ["transfer", text]
    when /お待ち|待って|少々/
      ["wait", text]
    when /結構|必要ありません|間に合|いらない|大丈夫/
      ["rejection", text]
    when /不在|外出|席を外|いません|おりません|出かけ|留守/
      ["absent", text]
    when /用件/
      ["inquiry", text]
    else
      ["unknown", text]
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