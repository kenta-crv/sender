module Twilio
  class VoiceController < BaseController
    before_action :find_call, except: [:operator_join]

    # POST /twilio/voice — 通話接続時、相手の挨拶を待つ
    def voice
      return head(:not_found) unless @call

      @call.update(flow_phase: 'talking', twilio_call_sid: params['CallSid']) if @call.twilio_call_sid.blank?
      @call.append_call_turn!('us', TwilioService.script_text('greeting'), script: 'greeting')
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
      script = TwilioService.choose_script(speech_result, purpose_played: TwilioService.purpose_played?(@call))
      hangup = TwilioService.hangup_script?(script)

      Rails.logger.info("[TWILIO:GATHER] call_id=#{@call.id} SpeechResult='#{speech_result}' script=#{script}")

      @call.append_call_turn!('them', speech_result, script: script)
      @call.update(speech_confidence: confidence.to_f)
      @call.append_call_turn!('us', TwilioService.script_text(script), script: script)

      render_twiml builder.gather_script_response(@call, script, hangup: hangup)
    end

    def stream_result
      return head(:not_found) unless @call

      script = params['script'].presence || 'repeat'
      hangup = params['hangup'] == '1' || TwilioService.hangup_script?(script)
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

      if @call.flow_phase == 'ended' || TwilioService.hangup_script?(@call.speech_category)
        render_twiml Twilio::TwiML::VoiceResponse.new { |r| r.hangup }
      elsif @call.flow_phase == 'repeat_wait'
        @call.append_call_turn!('us', TwilioService.script_text('closing'), script: 'closing')
        if stream_mode?
          render_twiml builder.stream_script_response(@call, 'closing', wss_url, hangup: true)
        else
          render_twiml builder.gather_script_response(@call, 'closing', hangup: true)
        end
      else
        @call.update(flow_phase: 'repeat_wait')
        @call.append_call_turn!('us', TwilioService.script_text('repeat'), script: 'repeat')
        if stream_mode?
          render_twiml builder.stream_script_response(@call, 'repeat', wss_url, hangup: false)
        else
          render_twiml builder.gather_script_response(@call, 'repeat', hangup: false)
        end
      end
    end

    # POST /twilio/transfer — Conference転送
    def transfer
      return head(:not_found) unless @call

      conference_name = "transfer_#{@call.id}"
      config = TwilioConfig.current

      already_dialed = @call.transferred_to.present?
      Rails.logger.info("[TWILIO:TRANSFER] call_id=#{@call.id} → Conference '#{conference_name}' (eager dial #{already_dialed ? 'done' : 'not yet'})")

      @call.update(flow_phase: 'transfer', transferred_to: config.operator_number)

      # 既に wait 段階で eager dial 済みならスキップ
      unless already_dialed
        Thread.new do
          begin
            service = TwilioService.new
            service.call_operator_to_conference(conference_name, base_url)
          rescue => e
            Rails.logger.error("[TWILIO:TRANSFER] オペレーター発信エラー: #{e.message}")
          end
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
