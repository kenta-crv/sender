class TwimlBuilder
  AUDIO_DIR = Rails.root.join('public', 'audio').freeze

  def initialize(config = nil)
    @config = config || TwilioConfig.current
  end

  def voice_response(call)
    gather_script_response(call, 'greeting', hangup: false)
  end

  def greeting_response(call)
    gather_script_response(call, 'greeting', hangup: false)
  end

  def gather_script_response(call, script_key, hangup:)
    text = TwilioService.script_text(script_key, @config)
    Twilio::TwiML::VoiceResponse.new do |r|
      if hangup
        twiml_say(r, text) if text.present?
        r.pause(length: 1)
        r.hangup
      else
        r.gather(
          input: "speech",
          language: @config.voice_language,
          hints: @config.speech_hints,
          action: "/twilio/gather?call_id=#{call.id}",
          method: "POST",
          timeout: 15,
          speech_timeout: "auto",
          barge_in: true
        ) do |g|
          twiml_say(g, text) if text.present?
        end
        r.redirect("/twilio/stream_fallback?call_id=#{call.id}", method: "POST")
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

  def stream_voice_response(call, wss_url)
    stream_script_response(call, 'greeting', wss_url, hangup: false)
  end

  def stream_greeting_response(call, wss_url)
    stream_script_response(call, 'greeting', wss_url, hangup: false)
  end

  def stream_script_response(call, script_key, wss_url, hangup:)
    text = TwilioService.script_text(script_key, @config)
    Twilio::TwiML::VoiceResponse.new do |r|
      twiml_say(r, text) if text.present?
      if hangup
        r.pause(length: 1)
        r.hangup
      else
        r.start do |s|
          s.stream(url: wss_url) do |st|
            st.parameter(name: 'call_id', value: call.id.to_s)
            st.parameter(name: 'phase', value: 'talking')
          end
        end
        r.pause(length: 60)
        r.redirect("/twilio/stream_fallback?call_id=#{call.id}", method: "POST")
      end
    end
  end

  private

  def twiml_say(response, text)
    response.say(message: text, language: @config.voice_language, voice: @config.voice_name)
  end

  # 事前録音音声があれば<Play>で再生、なければTTS<Say>にフォールバック
  # node: VoiceResponse または Gather ブロック内の g（バージイン対応）
  # key: :greeting, :absent, :inquiry, :rejection, :transfer, :wait
  # default_text: TwilioConfig側にも文言がない場合のリテラル文字列
  def play_or_say(node, key, default_text: nil)
    audio_file = AUDIO_DIR.join("#{key}.mp3")
    if File.exist?(audio_file)
      base_url = ENV.fetch('NGROK_URL', ENV.fetch('APP_BASE_URL', ''))
      node.play(url: "#{base_url}/audio/#{key}.mp3")
    else
      text = (@config.send("#{key}_text") rescue nil) || default_text
      twiml_say(node, text) if text.present?
    end
  end
end
