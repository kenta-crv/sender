module Twilio
  class VoiceController < BaseController
    before_action :find_call

    # POST /twilio/voice — 通話接続時、相手の挨拶を待つ
    def voice
      # 公開接続の健全性確認（実通話ではない）
      if params[:call_id].to_s == 'health'
        render_twiml(
          Twilio::TwiML::VoiceResponse.new do |r|
            r.say(message: 'ok', language: 'ja-JP', voice: TwilioConfig.current.voice_name)
          end
        )
        return
      end

      return head(:not_found) unless @call

      @call.update(flow_phase: 'talking', twilio_call_sid: params['CallSid']) if @call.twilio_call_sid.blank?
      greeting = TwilioService.script_text('greeting', @call)
      @call.append_call_turn!('us', greeting, script: 'greeting')
      @call.remember_context!(them: '', script: 'greeting', us: greeting)
      Rails.logger.info("[TWILIO:VOICE] CallSid=#{params['CallSid']} call_id=#{@call.id} stream_mode=#{stream_mode?}")

      if TwilioService.bidirectional_call?(@call)
        render_bidirectional
      elsif stream_mode?
        render_twiml builder.stream_voice_response(@call, wss_url)
      else
        render_twiml builder.voice_response(@call)
      end
    end

    def greeting
      return head(:not_found) unless @call

      Rails.logger.info("[TWILIO:GREETING] call_id=#{@call.id} flow_phase=#{@call.flow_phase}")
      @call.update(flow_phase: 'talking') unless @call.flow_phase == 'ended'

      if TwilioService.bidirectional_call?(@call)
        render_bidirectional
      elsif stream_mode?
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
      prepare_transfer_if_needed!(script)
      us_text = TwilioService.script_text(script, @call)
      @call.append_call_turn!('us', us_text, script: script)
      @call.remember_context!(them: speech_result, script: script, us: us_text)
      @call.save_selected_status!(script) if hangup
      DialTransferService.cancel_operator!(@call) if hangup

      render_twiml builder.gather_script_response(@call, script, hangup: hangup)
    end

    def stream_result
      return head(:not_found) unless @call

      if params['played'] == '1'
        render_played_handoff
        return
      end

      script = params['script'].presence || 'repeat'
      hangup = params['hangup'] == '1' || TwilioService.hangup_script?(script)
      prepare_transfer_if_needed!(script)
      us_text = TwilioService.script_text(script, @call)
      @call.append_call_turn!('us', us_text, script: script) unless TwilioService.transfer_script?(script)
      @call.remember_context!(them: '', script: script, us: us_text)
      @call.save_selected_status!(script) if hangup
      DialTransferService.cancel_operator!(@call) if hangup
      Rails.logger.info("[TWILIO:STREAM_RESULT] call_id=#{@call.id} script=#{script} hangup=#{hangup}")

      if TwilioService.transfer_script?(script)
        @call.append_call_turn!('us', us_text, script: script)
        render_twiml builder.transfer_response(@call)
      elsif stream_mode?
        render_twiml builder.stream_script_response(@call, script, wss_url, hangup: hangup)
      else
        render_twiml builder.gather_script_response(@call, script, hangup: hangup)
      end
    end

    def transfer
      return head(:not_found) unless @call

      DialTransferService.start_operator!(@call)
      text = DialTransferService::THANKS_TEXT
      @call.append_call_turn!('us', text, script: 'transfer')
      @call.update(flow_phase: 'transfer')
      render_twiml builder.transfer_response(@call)
    end

    def operator_join
      return head(:not_found) unless @call

      Rails.logger.info("[TWILIO:OPERATOR_JOIN] call_id=#{@call.id}")
      render_twiml builder.operator_join_response(@call)
    end

    def conference_wait
      render_twiml builder.conference_wait_response
    end

    def conference_status
      return head(:ok) unless @call

      event = params['StatusCallbackEvent'].to_s
      Rails.logger.info("[TWILIO:CONFERENCE] call_id=#{@call.id} event=#{event}")
      if event == 'participant-join'
        @call.update(flow_phase: 'transferred') if @call.flow_phase == 'transfer'
      end
      head :ok
    end

    def stream_fallback
      return head(:not_found) unless @call

      Rails.logger.info("[TWILIO:STREAM_FALLBACK] call_id=#{@call.id} flow_phase=#{@call.flow_phase}")

      if @call.flow_phase == 'ended' || Call::AI_STATUS_ITEMS.include?(@call.status.to_s)
        render_twiml Twilio::TwiML::VoiceResponse.new { |r| r.hangup }
      else
        script = DialFlowEngine.on_listen_timeout(@call)
        hangup = TwilioService.hangup_script?(script)
        @call.update(flow_phase: hangup ? 'ended' : 'repeat_wait')
        us_text = TwilioService.script_text(script, @call)
        @call.append_call_turn!('us', us_text, script: script)
        @call.remember_context!(them: '', script: script, us: us_text)
        @call.save_selected_status!(script) if hangup
        DialTransferService.cancel_operator!(@call) if hangup
        if TwilioService.bidirectional_call?(@call)
          render_bidirectional
        elsif stream_mode?
          render_twiml builder.stream_script_response(@call, script, wss_url, hangup: hangup)
        else
          render_twiml builder.gather_script_response(@call, script, hangup: hangup)
        end
      end
    end

    private

    def prepare_transfer_if_needed!(script)
      return unless TwilioService.transfer_script?(script)

      DialTransferService.start_operator!(@call)
    end

    def render_played_handoff
      script = params['script'].presence || 'clarify'
      hangup = params['hangup'] == '1' || TwilioService.hangup_script?(script)
      Rails.logger.info("[TWILIO:PLAYED] call_id=#{@call.id} script=#{script} hangup=#{hangup}")
      if TwilioService.transfer_script?(script)
        render_twiml builder.transfer_response(@call, speak: false)
      elsif hangup
        render_twiml Twilio::TwiML::VoiceResponse.new { |r| r.hangup }
      elsif TwilioService.bidirectional_call?(@call)
        render_bidirectional
      else
        render_twiml builder.gather_script_response(@call, script, hangup: false)
      end
    end

    def render_bidirectional
      DialPlaybackCache.preload!(@call.dial_script) if @call.dial_script
      render_twiml builder.connect_stream_response(@call, wss_url)
    rescue DialPlaybackCache::NotReady => e
      Rails.logger.error("[TWILIO:VOICE] 録音の事前変換ができません call_id=#{@call.id} #{e.message}")
      render_twiml builder.voice_response(@call)
    end

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
