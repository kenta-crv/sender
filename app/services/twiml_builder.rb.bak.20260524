class TwimlBuilder
  def initialize(config = nil)
    @config = config || TwilioConfig.current
  end

  # 初期応答: 相手の挨拶を待つGather
  def voice_response(call)
    Twilio::TwiML::VoiceResponse.new do |r|
      r.gather(
        input: "speech",
        language: @config.voice_language,
        hints: "もしもし,はい,お世話になっております,お電話ありがとうございます",
        action: "/twilio/greeting?call_id=#{call.id}",
        method: "POST",
        timeout: @config.gather_timeout,
        speech_timeout: 1
      )
      # タイムアウト時（無言で出た場合）→ そのまま挨拶へ
      r.redirect("/twilio/greeting?call_id=#{call.id}", method: "POST")
    end
  end

  # 相手の挨拶検知後 → TTS挨拶 → 応答待ちGather
  def greeting_response(call)
    Twilio::TwiML::VoiceResponse.new do |r|
      twiml_say(r, @config.greeting_text)
      r.gather(
        input: "speech",
        language: @config.voice_language,
        hints: @config.speech_hints,
        action: "/twilio/gather?call_id=#{call.id}",
        method: "POST",
        timeout: @config.gather_timeout,
        speech_timeout: @config.speech_timeout
      )
      # Gatherタイムアウト時 → オペレーター転送
      r.redirect("/twilio/transfer?call_id=#{call.id}", method: "POST")
    end
  end

  # 音声認識結果に基づく応答
  def gather_response(call, category)
    Twilio::TwiML::VoiceResponse.new do |r|
      case category
      when "absent"
        twiml_say(r, @config.absent_text)
        r.pause(length: 2)
        r.hangup
      when "inquiry"
        twiml_say(r, @config.inquiry_text)
        r.pause(length: 2)
        r.hangup
      when "rejection"
        twiml_say(r, @config.rejection_text)
        r.pause(length: 2)
        r.hangup
      when "transfer"
        r.redirect("/twilio/transfer?call_id=#{call.id}", method: "POST")
      when "wait"
        r.gather(
          input: "speech",
          language: @config.voice_language,
          hints: @config.speech_hints,
          action: "/twilio/gather?call_id=#{call.id}",
          method: "POST",
          timeout: 15,
          speech_timeout: @config.speech_timeout
        )
        # タイムアウト時はオペレーター転送
        r.redirect("/twilio/transfer?call_id=#{call.id}", method: "POST")
      else
        twiml_say(r, @config.transfer_text || "オペレーターにおつなぎいたします。")
        r.redirect("/twilio/transfer?call_id=#{call.id}", method: "POST")
      end
    end
  end

  # Conference転送（発信者側）
  def transfer_response(call, conference_name, base_url)
    Twilio::TwiML::VoiceResponse.new do |r|
      r.dial do |d|
        d.conference(
          conference_name,
          start_conference_on_enter: true,
          end_conference_on_exit: true,
          wait_url: '',
          status_callback: "#{base_url}/twilio/conference/status",
          status_callback_event: "join leave"
        )
      end
    end
  end

  # オペレーターConference参加
  def operator_join_response(conference_name, base_url)
    Twilio::TwiML::VoiceResponse.new do |r|
      r.dial do |d|
        d.conference(
          conference_name,
          start_conference_on_enter: true,
          end_conference_on_exit: false,
          status_callback: "#{base_url}/twilio/conference/status",
          status_callback_event: "join leave"
        )
      end
    end
  end

  # --- Stream Mode ---

  # ストリームモード: 初期応答（相手の挨拶検知）
  # initialフェーズはGatherで十分（ストリーム不要）
  def stream_voice_response(call, wss_url)
    voice_response(call)
  end

  # ストリームモード: TTS挨拶 → リアルタイム音声認識
  def stream_greeting_response(call, wss_url)
    Twilio::TwiML::VoiceResponse.new do |r|
      r.start do |s|
        s.stream(url: wss_url) do |st|
          st.parameter(name: 'call_id', value: call.id.to_s)
          st.parameter(name: 'phase', value: 'greeting')
        end
      end
      twiml_say(r, @config.greeting_text)
      # ストリームがリアルタイムで認識→CallRedirectorのcalls.update()でリダイレクトされるまで待機
      r.pause(length: 120)
      # フォールバック: 認識されなかった場合のみここに到達
      r.redirect("/twilio/stream_fallback?call_id=#{call.id}", method: "POST")
    end
  end

  private

  def twiml_say(response, text)
    response.say(message: text, language: @config.voice_language, voice: @config.voice_name)
  end
end
