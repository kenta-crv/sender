class CallRedirector
  def initialize
    @client = Twilio::REST::Client.new(
      ENV.fetch('TWILIO_ACCOUNT_SID'),
      ENV.fetch('TWILIO_AUTH_TOKEN')
    )
    @base_url = ENV.fetch('NGROK_URL', ENV.fetch('APP_BASE_URL', ''))
  end

  def redirect_call(call_sid, call_id, category)
    Rails.logger.info("[CallRedirector] call_id=#{call_id} category=#{category} → redirecting")

    case category
    when "transfer"
      @client.calls(call_sid).update(
        url: "#{@base_url}/twilio/transfer?call_id=#{call_id}",
        method: 'POST'
      )
    when "wait"
      # 継続リスニング — リダイレクトしない
      Rails.logger.info("[CallRedirector] call_id=#{call_id} wait — 継続リスニング")
    else
      # absent, inquiry, rejection, unknown
      @client.calls(call_sid).update(
        url: "#{@base_url}/twilio/stream_result?call_id=#{call_id}&category=#{category}",
        method: 'POST'
      )
    end
  rescue => e
    Rails.logger.error("[CallRedirector] call_id=#{call_id} error: #{e.message}")
  end
end
