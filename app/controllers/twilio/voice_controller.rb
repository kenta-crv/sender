module Twilio
  class VoiceController < BaseController
    before_action :find_call

    # POST /twilio/voice — 通話接続時、相手の挨拶を待つ
    def voice
      return head(:not_found) unless @call

      @call.update(flow_phase: 'talking', twilio_call_sid: params['CallSid']) if @call.twilio_call_sid.blank?
      @call.append_call_turn!('us', TwilioService.script_text('greeting', @call), script: 'greeting')
      Rails.logger.info("[TWILIO:VOICE] CallSid=#{params['CallSid']} call_id=#{@call.id} stream_mode=#{stream_mode?}")

      if stream_mode?
        render_twiml builder.stream_voice_response(@call, wss_url)
      else
        render_twiml builder.voice_response(@call)
      end
    end

    def greeting
      return head(:not_found) unless @call

      Rails.logger.info("[TWILIO:GREETING] call_id=#{@call.id} flow_phase=#{@call.flow_phase}")
      @call.update(flow_phase: 'talking') unless @call.flow_phase == 'ended'

      if stream_mode?
        render_twiml builder.stream_greeting_response(@call, wss_url)
      else
        render_twiml builder.greeting_response(@call)
      end
    end

    def gather
      return head(:not_found) unless @call

      speech_result = TwilioService.utf8_speech(params['SpeechResult'])
      confidence = params['Confidence']
      script = TwilioService.choose_script(speech_result, call: @call)
      hangup = TwilioService.hangup_script?(script)

      Rails.logger.info("[TWILIO:GATHER] call_id=#{@call.id} SpeechResult='#{speech_result}' script=#{script}")

      @call.append_call_turn!('them', speech_result, script: script)
      @call.update(speech_confidence: confidence.to_f)
      @call.append_call_turn!('us', TwilioService.script_text(script, @call), script: script)
      @call.save_selected_status!(script) if hangup

      render_twiml builder.gather_script_response(@call, script, hangup: hangup)
    end

    def stream_result
      return head(:not_found) unless @call

      script = params['script'].presence || 'repeat'
      hangup = params['hangup'] == '1' || TwilioService.hangup_script?(script)
      @call.append_call_turn!('us', TwilioService.script_text(script, @call), script: script)
      @call.save_selected_status!(script) if hangup
      Rails.logger.info("[TWILIO:STREAM_RESULT] call_id=#{@call.id} script=#{script} hangup=#{hangup}")

      if stream_mode?
        render_twiml builder.stream_script_response(@call, script, wss_url, hangup: hangup)
      else
        render_twiml builder.gather_script_response(@call, script, hangup: hangup)
      end
    end

    def stream_fallback
      return head(:not_found) unless @call

      Rails.logger.info("[TWILIO:STREAM_FALLBACK] call_id=#{@call.id} flow_phase=#{@call.flow_phase}")

      if @call.flow_phase == 'ended' || Call.StatuItems.include?(@call.status)
        render_twiml Twilio::TwiML::VoiceResponse.new { |r| r.hangup }
      else
        @call.update(flow_phase: 'repeat_wait')
        @call.append_call_turn!('us', TwilioService.script_text('repeat', @call), script: 'repeat')
        if stream_mode?
          render_twiml builder.stream_script_response(@call, 'repeat', wss_url, hangup: false)
        else
          render_twiml builder.gather_script_response(@call, 'repeat', hangup: false)
        end
      end
    end

    private

    def stream_mode?
      TwilioConfig.current.stream_mode_enabled?
    end

    def wss_url
      # ngrokのhttps → wss に変換
      base = TwilioService.public_base_url.presence || request.base_url
      base.sub(/\Ahttps?/, 'wss') + '/media-stream'
    end
  end
end
