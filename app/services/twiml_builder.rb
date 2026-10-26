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
    text = TwilioService.script_text(script_key, call)
    Twilio::TwiML::VoiceResponse.new do |r|
      if hangup
        twiml_say(r, text) if text.present?
        r.pause(length: 1)
        r.hangup
      elsif TwilioService.transfer_script?(script_key)
        transfer_after_thanks(r, call, text)
      else
        base = TwilioService.public_base_url
        # 読み上げ中に聞き取りを重ねると、先方の声や回線音で文章が途中で切れる。
        twiml_say(r, text) if text.present?
        r.pause(length: 1)
        r.gather(
          input: "speech",
          language: @config.voice_language,
          hints: @config.speech_hints,
          action: "#{base}/twilio/gather?call_id=#{call.id}",
          method: "POST",
          timeout: 8,
          speech_timeout: "auto",
          barge_in: true
        )
        r.redirect("#{base}/twilio/stream_fallback?call_id=#{call.id}", method: "POST")
      end
    end
  end

  def connect_stream_response(call, wss_url)
    Twilio::TwiML::VoiceResponse.new do |r|
      r.connect do |c|
        c.stream(url: wss_url) do |st|
          st.parameter(name: 'call_id', value: call.id.to_s)
          st.parameter(name: 'phase', value: 'talking')
          st.parameter(name: 'mode', value: 'bidirectional')
        end
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
    text = TwilioService.script_text(script_key, call)
    Twilio::TwiML::VoiceResponse.new do |r|
      if TwilioService.transfer_script?(script_key)
        transfer_after_thanks(r, call, text)
      else
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
          r.redirect("#{TwilioService.public_base_url}/twilio/stream_fallback?call_id=#{call.id}", method: "POST")
        end
      end
    end
  end

  # お礼を話した直後に、待ち音なしで担当者と合流する。
  def transfer_response(call, speak: true)
    text = speak ? DialTransferService::THANKS_TEXT : nil
    Twilio::TwiML::VoiceResponse.new do |r|
      transfer_after_thanks(r, call, text)
    end
  end

  def operator_join_response(call)
    name = DialTransferService.conference_name(call)
    silent_conference(name, end_on_exit: false)
  end

  def conference_wait_response
    Twilio::TwiML::VoiceResponse.new do |r|
      r.pause(length: 60)
    end
  end

  private

  def transfer_after_thanks(response, call, text)
    twiml_say(response, text) if text.present?
    name = DialTransferService.conference_name(call)
    base = TwilioService.public_base_url
    response.dial do |d|
      d.conference(
        name,
        beep: false,
        start_conference_on_enter: true,
        end_conference_on_exit: true,
        wait_url: "#{base}/twilio/conference_wait",
        wait_method: 'POST',
        status_callback: "#{base}/twilio/conference_status?call_id=#{call.id}",
        status_callback_event: 'start end join leave'
      )
    end
  end

  def silent_conference(name, end_on_exit:)
    base = TwilioService.public_base_url
    Twilio::TwiML::VoiceResponse.new do |r|
      r.dial do |d|
        d.conference(
          name,
          beep: false,
          start_conference_on_enter: true,
          end_conference_on_exit: end_on_exit,
          wait_url: "#{base}/twilio/conference_wait",
          wait_method: 'POST'
        )
      end
    end
  end

  def twiml_say(response, text)
    response.say(message: text, language: @config.voice_language, voice: @config.voice_name)
  end

  # 事前録音音声があれば<Play>で再生、なければTTS<Say>にフォールバック
  def play_or_say(node, key, default_text: nil)
    audio_file = AUDIO_DIR.join("#{key}.mp3")
    if File.exist?(audio_file)
      base_url = TwilioService.public_base_url
      node.play(url: "#{base_url}/audio/#{key}.mp3")
    else
      text = (@config.send("#{key}_text") rescue nil) || default_text
      twiml_say(node, text) if text.present?
    end
  end
end
