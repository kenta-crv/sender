module Twilio
  class BaseController < ActionController::Base
    skip_before_action :verify_authenticity_token
    before_action :validate_twilio_request

    private

    def validate_twilio_request
      return if ENV['SKIP_TWILIO_VALIDATION'] == 'true'

      auth_token = ENV['TWILIO_AUTH_TOKEN']
      signature = request.headers['X-Twilio-Signature']

      if auth_token.blank? || signature.blank?
        Rails.logger.warn "[Twilio] Webhook rejected: missing auth token or signature"
        head :unauthorized
        return
      end

      validator = Twilio::Security::RequestValidator.new(auth_token)
      unless validator.validate(request.original_url, request.request_parameters, signature)
        Rails.logger.warn "[Twilio] Invalid webhook signature for #{request.original_url}"
        head :unauthorized
      end
    end

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
