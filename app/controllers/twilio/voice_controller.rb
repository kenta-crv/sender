module Twilio
  class VoiceController < BaseController
    before_action :find_call, except: [:operator_join]

    # POST /twilio/voice — 通話接続時、相手の挨拶を待つ
    def voice
      return head(:not_found) unless @call

      @call.update(flow_phase: 'greeting', twilio_call_sid: params['CallSid']) if @call.twilio_call_sid.blank?
      Rails.logger.info("[TWILIO:VOICE] CallSid=#{params['CallSid']} call_id=#{@call.id} stream_mode=#{stream_mode?}")

      if stream_mode?
        render_twiml builder.stream_voice_response(@call, wss_url)
      else
        render_twiml builder.voice_response(@call)
      end
    end

    # POST /twilio/greeting — 相手の挨拶検知後、TTS挨拶 → 応答待ち
    def greeting
      return head(:not_found) unless @call

      Rails.logger.info("[TWILIO:GREETING] call_id=#{@call.id} SpeechResult='#{params['SpeechResult']}'")
      @call.update(flow_phase: 'gather')

      if stream_mode?
        render_twiml builder.stream_greeting_response(@call, wss_url)
      else
        render_twiml builder.greeting_response(@call)
      end
    end

    # POST /twilio/gather — 音声認識結果を受信・分類（Gatherモード用）
    def gather
      return head(:not_found) unless @call

      speech_result = params['SpeechResult']
      confidence = params['Confidence']
      category, _matched = TwilioService.classify_speech(speech_result)

      Rails.logger.info("[TWILIO:GATHER] call_id=#{@call.id} SpeechResult='#{speech_result}' Confidence=#{confidence} Category=#{category}")

      @call.update(
        speech_result: speech_result,
        speech_category: category,
        speech_confidence: confidence.to_f,
        flow_phase: category
      )

      render_twiml builder.gather_response(@call, category)
    end

    # POST /twilio/stream_result — ストリームモード: 分類結果に基づくTwiML応答
    def stream_result
      return head(:not_found) unless @call

      category = params['category']
      Rails.logger.info("[TWILIO:STREAM_RESULT] call_id=#{@call.id} category=#{category}")

      render_twiml builder.gather_response(@call, category)
    end

    # POST /twilio/transfer — Conference転送
    def transfer
      return head(:not_found) unless @call

      conference_name = "transfer_#{@call.id}"
      config = TwilioConfig.current

      Rails.logger.info("[TWILIO:TRANSFER] call_id=#{@call.id} → Conference '#{conference_name}'")

      @call.update(flow_phase: 'transfer', transferred_to: config.operator_number)

      # オペレーターをConferenceに呼び出し（非同期）
      Thread.new do
        begin
          service = TwilioService.new
          service.call_operator_to_conference(conference_name, base_url)
        rescue => e
          Rails.logger.error("[TWILIO:TRANSFER] オペレーター発信エラー: #{e.message}")
        end
      end

      render_twiml builder.transfer_response(@call, conference_name, base_url)
    end

    # POST /twilio/operator_join — オペレーターConference参加
    def operator_join
      conference_name = params['conference']
      Rails.logger.info("[TWILIO:OPERATOR_JOIN] Conference='#{conference_name}'")

      render_twiml builder.operator_join_response(conference_name, base_url)
    end

    private

    def stream_mode?
      TwilioConfig.current.stream_mode_enabled?
    end

    def wss_url
      # ngrokのhttps → wss に変換
      base = ENV.fetch('NGROK_URL', ENV.fetch('APP_BASE_URL', ''))
      base.sub(/\Ahttps?/, 'wss') + '/media-stream'
    end
  end
end
