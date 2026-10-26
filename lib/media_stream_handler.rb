require 'json'
require 'base64'
require_relative 'google_speech_stream'
require_relative 'call_redirector'
require_relative 'bidirectional_call_session'

class MediaStreamHandler
  def initialize(ws)
    @ws = ws
    @call_sid = nil
    @call_id = nil
    @stream_sid = nil
    @speech_stream = nil
    @phase = nil
    @redirected = false
    @session = nil
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
    when 'mark'
      @session&.on_mark(data.dig('mark', 'name'))
    when 'stop'
      handle_stop(data)
    end
  rescue => e
    Rails.logger.error("[MediaStreamHandler] on_message error: #{e.message}")
  end

  def on_close(event)
    @session&.finish
    @speech_stream&.stop
    Rails.logger.info("[MediaStreamHandler] Closed call_id=#{@call_id}")
  end

  private

  def handle_start(data)
    @speech_stream&.stop

    @call_sid = data.dig('start', 'callSid')
    @stream_sid = data.dig('start', 'streamSid')
    custom_params = data.dig('start', 'customParameters') || {}
    @call_id = custom_params['call_id']
    @phase = custom_params['phase'] || 'greeting'
    @redirected = false

    Rails.logger.info("[MediaStreamHandler] Start: call_id=#{@call_id} call_sid=#{@call_sid} phase=#{@phase}")

    call = nil
    if @call_id
      call = Call.find_by(id: @call_id)
      call&.update(stream_sid: @stream_sid)
    end
    if custom_params['mode'] == 'bidirectional' && TwilioService.bidirectional_call?(call)
      @session = BidirectionalCallSession.new(
        @ws,
        call_id: @call_id,
        call_sid: @call_sid,
        stream_sid: @stream_sid,
        call: call
      )
    end

    config = TwilioConfig.current
    hints = (config.speech_hints || '').split(',').map(&:strip).reject(&:empty?)

    @speech_stream = GoogleSpeechStream.new(
      call_id: @call_id,
      hints: hints,
      single_utterance: false,
      on_result: method(:on_speech_result),
      on_interim: method(:on_speech_interim),
      on_error: method(:on_speech_error)
    )
    @speech_stream.start
    @session&.start!
  end

  def handle_media(data)
    payload = data.dig('media', 'payload')
    return unless payload
    return if data.dig('media', 'track') == 'outbound'

    raw_audio = Base64.decode64(payload)
    @speech_stream&.feed_audio(raw_audio)
    @session&.feed(raw_audio)
  end

  def handle_stop(data)
    Rails.logger.info("[MediaStreamHandler] Stop: call_id=#{@call_id}")
    @session&.finish
    @speech_stream&.stop
    @speech_stream = nil
  end

  def on_speech_interim(transcript, confidence)
    if @session
      @session.on_interim(transcript, confidence)
      return
    end
    return unless @call_id

    transcript = TwilioService.utf8_speech(transcript)
    return if transcript.blank?

    CallTranscriptBroadcaster.broadcast(
      @call_id,
      speaker: 'them',
      text: transcript,
      interim: true
    )
  end

  def on_speech_result(transcript, confidence)
    if @session
      @session.on_final(transcript, confidence)
      return
    end
    return unless @call_id && @call_sid

    @mutex.synchronize do
      return if @redirected
    end

    transcript = TwilioService.utf8_speech(transcript)
    call = Call.find_by(id: @call_id)
    return unless call

    script = TwilioService.choose_script(transcript, call: call)
    hangup = TwilioService.hangup_script?(script)
    transfer = TwilioService.transfer_script?(script)
    Rails.logger.info("[MediaStreamHandler] call_id=#{@call_id} transcript='#{transcript}' script=#{script}")

    call.append_call_turn!('them', transcript, script: script)
    call.update(speech_confidence: confidence)

    DialTransferService.start_operator!(call) if transfer

    us_text = TwilioService.script_text(script, call)
    call.append_call_turn!('us', us_text, script: script) unless transfer
    call.remember_context!(them: transcript, script: script, us: us_text)
    call.save_selected_status!(script) if hangup
    DialTransferService.cancel_operator!(call) if hangup

    do_redirect do
      if transfer
        CallRedirector.new.redirect_transfer(@call_sid, @call_id)
      else
        CallRedirector.new.redirect_script(@call_sid, @call_id, script, hangup: hangup)
      end
    end
  end

  def on_speech_error(error)
    Rails.logger.error("[MediaStreamHandler] Google Speech error: #{error.message}")
    if @session
      @session.on_error(error)
      return
    end

    do_redirect do
      if @call_sid && @call_id
        call = Call.find_by(id: @call_id)
        script = call ? DialFlowEngine.on_listen_timeout(call) : 'clarify'
        hangup = TwilioService.hangup_script?(script)
        if hangup && call
          call.save_selected_status!(script)
          DialTransferService.cancel_operator!(call)
        end
        CallRedirector.new.redirect_script(@call_sid, @call_id, script, hangup: hangup)
      end
    end
  end

  def do_redirect
    @mutex.synchronize do
      return if @redirected
      @redirected = true
    end

    begin
      yield
    rescue => e
      Rails.logger.error("[MediaStreamHandler] redirect error: #{e.message}")
      @mutex.synchronize { @redirected = false }
    end
  end
end
