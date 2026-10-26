module Twilio
  class PingController < ActionController::Base
    skip_before_action :verify_authenticity_token

    # GET/POST /twilio/ping — 公開URLが生きているかの確認用
    def show
      render plain: 'ok', content_type: 'text/plain'
    end
  end
end
