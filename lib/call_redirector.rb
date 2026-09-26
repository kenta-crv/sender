require 'cgi'

class CallRedirector
  def initialize
    @client = Twilio::REST::Client.new(
      ENV.fetch('TWILIO_ACCOUNT_SID'),
      ENV.fetch('TWILIO_AUTH_TOKEN')
    )
    @base_url = TwilioService.public_base_url
  end

  def redirect_script(call_sid, call_id, script, hangup:)
    if @base_url.blank?
      Rails.logger.error("[CallRedirector] 次の文章を返すアドレスが空です call_id=#{call_id}")
      return
    end

    hangup_q = hangup ? '1' : '0'
    script_q = CGI.escape(script.to_s)
    Rails.logger.info("[CallRedirector] call_id=#{call_id} script=#{script} hangup=#{hangup_q}")
    @client.calls(call_sid).update(
      url: "#{@base_url}/twilio/stream_result?call_id=#{call_id}&script=#{script_q}&hangup=#{hangup_q}",
      method: 'POST'
    )
  rescue => e
    Rails.logger.error("[CallRedirector] call_id=#{call_id} error: #{e.message}")
  end
end
