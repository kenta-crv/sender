module Twilio
  class BaseController < ActionController::Base
    skip_before_action :verify_authenticity_token

    private

    def render_twiml(response)
      render xml: response.to_s, content_type: 'text/xml'
    end

    def find_call
      @call = Call.find_by(id: params[:call_id]) || Call.find_by(twilio_call_sid: params['CallSid'])
    end

    def base_url
      ENV.fetch('NGROK_URL', ENV.fetch('APP_BASE_URL', request.base_url))
    end

    def builder
      @builder ||= TwimlBuilder.new
    end
  end
end
