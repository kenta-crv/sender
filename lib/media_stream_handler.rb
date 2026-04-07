require 'json'
require 'base64'
require_relative 'google_speech_stream'
require_relative 'call_redirector'

class MediaStreamHandler
  def initialize(ws)
    @ws = ws
    @call_sid = nil
    @call_id = nil
    @stream_sid = nil
    @speech_stream = nil
    @phase = nil
    @redirected = false  # リダイレクト済みフラグ（1回だけリダイレクト）
    @mutex = Mutex.new
  end

  def on_message(event)
    data = JSON.parse(event.data)

    case data['event']
    when 'connected'
      Rails.logger.info("[MediaStreamHandler] Connected")
    when 'start'
      handle_start(data)
    when 'media'
      handle_media(data)
    when 'stop'
      handle_stop(data)
    end
  rescue => e
    Rails.logger.error("[MediaStreamHandler] on_message error: #{e.message}")
  end

  def on_close(event)
    @speech_stream&.stop
    Rails.logger.info("[MediaStreamHandler] Closed call_id=#{@call_id}")
  end

  private

  def handle_start(data)
    # 既にストリームが動いていたら停止
    @speech_stream&.stop

    @call_sid = data.dig('start', 'callSid')
    @stream_sid = data.dig('start', 'streamSid')
    custom_params = data.dig('start', 'customParameters') || {}
    @call_id = custom_params['call_id']
    @phase = custom_params['phase'] || 'greeting'
    @redirected = false  # 新しいストリーム開始時にリセット

    Rails.logger.info("[MediaStreamHandler] Start: call_id=#{@call_id} call_sid=#{@call_sid} phase=#{@phase}")

    # Callレコードを更新
    if @call_id
      call = Call.find_by(id: @call_id)
      call&.update(stream_sid: @stream_sid)
    end

    # Google Speechストリーミング開始
    config = TwilioConfig.current
    hints = (config.speech_hints || '').split(',').map(&:strip).reject(&:empty?)

    @speech_stream = GoogleSpeechStream.new(
      call_id: @call_id,
      hints: hints,
      single_utterance: false,
      on_result: method(:on_speech_result),
      on_error: method(:on_speech_error)
    )
    @speech_stream.start
  end

  def handle_media(data)
    return unless @speech_stream

    payload = data.dig('media', 'payload')
    return unless payload

    raw_audio = Base64.decode64(payload)
    @speech_stream.feed_audio(raw_audio)
  end

  def handle_stop(data)
    Rails.logger.info("[MediaStreamHandler] Stop: call_id=#{@call_id}")
    @speech_stream&.stop
    @speech_stream = nil
  end

  def on_speech_result(transcript, confidence)
    return unless @call_id && @call_sid

    # スレッドセーフにリダイレクト済みチェック
    @mutex.synchronize do
      return if @redirected
    end

    # UTF-8に変換
    transcript = transcript.encode('UTF-8', invalid: :replace, undef: :replace, replace: '') unless transcript.encoding == Encoding::UTF_8

    # 分類
    category, _matched = TwilioService.classify_speech(transcript)

    Rails.logger.info("[MediaStreamHandler] call_id=#{@call_id} transcript='#{transcript}' category=#{category}")

    # Callレコードを更新
    call = Call.find_by(id: @call_id)
    if call
      call.update(
        speech_result: transcript,
        speech_category: category,
        speech_confidence: confidence,
        speech_detected_at: Time.current,
        flow_phase: category
      )
    end

    # 初期フェーズ（もしもし検知）の場合はgreetingにリダイレクト
    if @phase == 'initial'
      do_redirect do
        base_url = ENV.fetch('NGROK_URL', ENV.fetch('APP_BASE_URL', ''))
        Twilio::REST::Client.new(
          ENV.fetch('TWILIO_ACCOUNT_SID'),
          ENV.fetch('TWILIO_AUTH_TOKEN')
        ).calls(@call_sid).update(
          url: "#{base_url}/twilio/greeting?call_id=#{@call_id}",
          method: 'POST'
        )
      end
      return
    end

    # 通常フェーズ: 分類結果に基づきリダイレクト（waitは除く）
    unless category == 'wait'
      do_redirect do
        redirector = CallRedirector.new
        redirector.redirect_call(@call_sid, @call_id, category)
      end
    end
  end

  def on_speech_error(error)
    Rails.logger.error("[MediaStreamHandler] Google Speech error: #{error.message}")

    # エラー時はGatherモードにフォールバック
    do_redirect do
      if @call_sid && @call_id
        base_url = ENV.fetch('NGROK_URL', ENV.fetch('APP_BASE_URL', ''))
        Twilio::REST::Client.new(
          ENV.fetch('TWILIO_ACCOUNT_SID'),
          ENV.fetch('TWILIO_AUTH_TOKEN')
        ).calls(@call_sid).update(
          url: "#{base_url}/twilio/greeting?call_id=#{@call_id}",
          method: 'POST'
        )
      end
    end
  end

  # リダイレクトを1回だけ実行する
  def do_redirect
    @mutex.synchronize do
      return if @redirected
      @redirected = true
    end

    begin
      yield
    rescue => e
      Rails.logger.error("[MediaStreamHandler] redirect error: #{e.message}")
      @mutex.synchronize { @redirected = false }  # 失敗時はリセット
    end
  end
end
