require 'cgi'

# お礼の一文の前に担当者へ先かけし、無音のまま同じ通話へ合流させる。
class DialTransferService
  THANKS_TEXT = 'お忙しい中ご対応ありがとうございます。'.freeze

  def self.conference_name(call)
    "front_transfer_#{call.id}"
  end

  def self.start_operator!(call)
    return if call.blank?
    return if call.operator_call_sid.present?

    config = TwilioConfig.current
    to = config.operator_number.to_s.strip
    if to.blank?
      Rails.logger.error("[DialTransfer] operator_number が空です call_id=#{call.id}")
      return
    end

    base_url = TwilioService.public_base_url
    if base_url.blank?
      Rails.logger.error("[DialTransfer] 公開URLが空です call_id=#{call.id}")
      return
    end

    client = Twilio::REST::Client.new(
      ENV.fetch('TWILIO_ACCOUNT_SID'),
      ENV.fetch('TWILIO_AUTH_TOKEN')
    )
    name = conference_name(call)
    operator_call = client.calls.create(
      to: TwilioService.to_e164(to),
      from: config.from_number,
      url: "#{base_url}/twilio/operator_join?call_id=#{call.id}&conference=#{CGI.escape(name)}",
      status_callback: "#{base_url}/twilio/status",
      status_callback_event: %w[initiated ringing answered completed],
      timeout: 30
    )
    call.update(
      operator_call_sid: operator_call.sid,
      transferred_to: to,
      flow_phase: 'transfer',
      conference_sid: name
    )
    Rails.logger.info("[DialTransfer] operator dial call_id=#{call.id} sid=#{operator_call.sid}")
  rescue => e
    Rails.logger.error("[DialTransfer] start_operator call_id=#{call&.id} error: #{e.message}")
  end

  def self.cancel_operator!(call)
    return if call.blank?
    sid = call.operator_call_sid
    return if sid.blank?

    TwilioService.new.hangup_call(sid)
    Rails.logger.info("[DialTransfer] cancel operator call_id=#{call.id} sid=#{sid}")
  rescue => e
    Rails.logger.error("[DialTransfer] cancel_operator call_id=#{call&.id} error: #{e.message}")
  end
end
