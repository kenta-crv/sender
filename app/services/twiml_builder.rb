class TwimlBuilder
  AUDIO_DIR = Rails.root.join('public', 'audio').freeze

  def initialize(config = nil)
    @config = config || TwilioConfig.current
  end

  # 初期応答: 出た後 2秒（もしもし発話の余地）→ 即 greeting へ
  # Twilio の Gather 検知時間（3-4秒）を回避するため、固定タイミングで greeting に進む
  def voice_response(call)
    Twilio::TwiML::VoiceResponse.new do |r|
      r.pause(length: 2)
      r.redirect("/twilio/greeting?call_id=#{call.id}", method: "POST")
    end
  end

  # 相手の挨拶検知後 → 応答待ちGather内で挨拶再生（バージイン: 再生中の発話で即遷移）
  # speech_timeout="auto" で Twilio が自然な区切りを判断（固定値より速い場合あり）
  def greeting_response(call)
    Twilio::TwiML::VoiceResponse.new do |r|
      r.gather(
        input: "speech",
        language: @config.voice_language,
        hints: @config.speech_hints,
        action: "/twilio/gather?call_id=#{call.id}",
        method: "POST",
        timeout: @config.gather_timeout,
        speech_timeout: "auto"
      ) do |g|
        play_or_say(g, :greeting)
      end
      # Gatherタイムアウト時 → オペレーター転送
      r.redirect("/twilio/transfer?call_id=#{call.id}", method: "POST")
    end
  end

  # 音声認識結果に基づく応答
  def gather_response(call, category)
    Twilio::TwiML::VoiceResponse.new do |r|
      case category
      when "absent"
        play_or_say(r, :absent)
        r.pause(length: 2)
        r.hangup
      when "inquiry"
        # 用件説明後は会話継続（再Gather）→ wait/transfer/rejection 等の次反応を待つ
        r.gather(
          input: "speech",
          language: @config.voice_language,
          hints: @config.speech_hints,
          action: "/twilio/gather?call_id=#{call.id}",
          method: "POST",
          timeout: 15,
          speech_timeout: "auto"
        ) do |g|
          play_or_say(g, :inquiry)
        end
        # タイムアウト時はオペレーター転送（フォロー目的）
        r.redirect("/twilio/transfer?call_id=#{call.id}", method: "POST")
      when "rejection"
        play_or_say(r, :rejection)
        r.pause(length: 2)
        r.hangup
      when "transfer"
        r.redirect("/twilio/transfer?call_id=#{call.id}", method: "POST")
      when "wait"
        # 担当者を待つ間は無音で待機（受付に「少々お待ちください」と言われた側は
        # 通常何も話さず待つのが自然なため、音声は再生しない）
        r.gather(
          input: "speech",
          language: @config.voice_language,
          hints: @config.speech_hints,
          action: "/twilio/gather?call_id=#{call.id}",
          method: "POST",
          timeout: 15,
          speech_timeout: "auto"
        )
        # タイムアウト時はオペレーター転送
        r.redirect("/twilio/transfer?call_id=#{call.id}", method: "POST")
      else
        # 未分類（もしもし・あー・雑音 等）→ 転送には飛ばず再度応答を待つ
        # bargein で greeting 中の発話が拾われたケースの誤転送防止
        r.gather(
          input: "speech",
          language: @config.voice_language,
          hints: @config.speech_hints,
          action: "/twilio/gather?call_id=#{call.id}",
          method: "POST",
          timeout: @config.gather_timeout,
          speech_timeout: "auto"
        )
        # それでも応答がなければオペレーター転送
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

  # ストリームモード: 初期応答（出た後 2秒の余地を挟んで greeting）
  # 出る → 2秒 もしもし発話の余地 → greeting 再生
  # Stream はこの2秒からリアルタイム認識スタート
  def stream_voice_response(call, wss_url)
    Twilio::TwiML::VoiceResponse.new do |r|
      r.start do |s|
        s.stream(url: wss_url) do |st|
          st.parameter(name: 'call_id', value: call.id.to_s)
          st.parameter(name: 'phase', value: 'greeting')
        end
      end
      r.pause(length: 2)
      play_or_say(r, :greeting)
      r.pause(length: 120)
      r.redirect("/twilio/stream_fallback?call_id=#{call.id}", method: "POST")
    end
  end

  # ストリームモード: 挨拶（TTS or 録音音声）→ リアルタイム音声認識
  def stream_greeting_response(call, wss_url)
    Twilio::TwiML::VoiceResponse.new do |r|
      r.start do |s|
        s.stream(url: wss_url) do |st|
          st.parameter(name: 'call_id', value: call.id.to_s)
          st.parameter(name: 'phase', value: 'greeting')
        end
      end
      play_or_say(r, :greeting)
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
