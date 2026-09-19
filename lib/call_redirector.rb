class CallRedirector
  def initialize
    @client = Twilio::REST::Client.new(
      ENV.fetch('TWILIO_ACCOUNT_SID'),
      ENV.fetch('TWILIO_AUTH_TOKEN')
    )
    @base_url = ENV.fetch('NGROK_URL', ENV.fetch('APP_BASE_URL', ''))
  end

  def redirect_script(call_sid, call_id, script, hangup:)
    hangup_q = hangup ? '1' : '0'
    Rails.logger.info("[CallRedirector] call_id=#{call_id} script=#{script} hangup=#{hangup_q}")
    @client.calls(call_sid).update(
      url: "#{@base_url}/twilio/stream_result?call_id=#{call_id}&script=#{script}&hangup=#{hangup_q}",
      method: 'POST'
    )
  rescue => e
    Rails.logger.error("[CallRedirector] call_id=#{call_id} error: #{e.message}")
  end
end
