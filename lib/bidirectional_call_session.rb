require 'base64'
require 'json'
require_relative 'utterance_vad'

# 原稿ID 1 の双方向ストリーム。途中の認識では再生も転送もしない。
class BidirectionalCallSession
  FINAL_WAIT_SEC = 0.4
  PREVIEW_WAIT_SEC = 2.0
  LISTEN_TIMEOUT_SEC = 8
  BARGE_MS = 200

  def initialize(ws, call_id:, call_sid:, stream_sid:, call: nil, persist: true, greet: true, decider: DialRealtimeDecider)
    @ws = ws
    @call_id = call_id
    @call_sid = call_sid
    @stream_sid = stream_sid
    @call = call
    @persist = persist
    @greet = greet
    @decider = decider
    @script_id = call&.dial_script_id
    @lock = Mutex.new
    @send_lock = Mutex.new
    @vad = UtteranceVad.new
    @finals = []
    @interim = ''
    @final_mono = nil
    @confidence = nil
    @listening = !greet
    @playing = false
    @play_gen = 0
    @busy = false
    @turn = 0
    @preview_gen = 0
    @preview_text = nil
    @preview_decision = nil
    @barge_ms = 0
    @quiet_since = nil
    @after = nil
    @closed = false
  end

  def start!
    return unless @greet

    play('greeting', turn_id: nil, kind: 'greeting')
  end

  def feed(mulaw_bytes)
    return if @closed || mulaw_bytes.nil? || mulaw_bytes.empty?

    if @playing
      note_barge(mulaw_bytes)
      return
    end
    return unless @listening

    if @vad.feed(mulaw_bytes)
      on_utterance_end
    else
      note_quiet
    end
  end

  def on_interim(transcript, _confidence)
    text = TwilioService.utf8_speech(transcript)
    return if text.blank?

    @lock.synchronize { @interim = text }
    broadcast(text, 'interim')
  end

  def on_final(transcript, confidence)
    text = TwilioService.utf8_speech(transcript)
    return if text.blank?

    @confidence = confidence
    @lock.synchronize do
      @finals << text
      @interim = ''
      @final_mono = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
    broadcast(text, 'final')
    start_preview
  end

  def on_mark(name)
    turn_id = name.to_s[/turn-(\d+)-first/, 1]
    return if turn_id.blank?

    CallLatencyLog.record(
      @call_id,
      'playback_mark',
      turn_id: turn_id.to_i,
      extra: { kind: 'utterance', name: name.to_s }
    )
  end

  def on_error(_error)
    return if @closed || @busy || @playing

    @busy = true
    @listening = false
    play('clarify', turn_id: nil, kind: 'error')
  end

  def finish
    @closed = true
    @play_gen += 1
    @listening = false
  end

  def wait_idle(seconds = 3)
    @worker&.join(seconds)
    @preview_thread&.join(seconds)
    @play_thread&.join(seconds)
  end

  private

  def on_utterance_end
    return if @busy

    @busy = true
    @listening = false
    @quiet_since = nil
    @turn += 1
    turn_id = @turn
    CallLatencyLog.record(@call_id, 'utterance_end', turn_id: turn_id, extra: { kind: 'utterance' })
    @worker = Thread.new do
      Rails.application.executor.wrap { commit_turn(turn_id) }
    end
  end

  def commit_turn(turn_id)
    text, doubt, final_mono = wait_for_stable
    CallLatencyLog.record(
      @call_id,
      'transcript_final',
      turn_id: turn_id,
      at_mono: final_mono,
      extra: { kind: 'utterance', doubt: doubt, text: text.to_s }
    )
    preview_thread = @preview_thread
    if preview_thread&.alive? && @preview_text == text
      preview_thread.join(PREVIEW_WAIT_SEC)
    end
    call = current_call
    decision = take_preview(text)
    decision ||= @decider.decide(text, call: call, stt_confidence: doubt ? 0.3 : @confidence)
    decision = escalate_unclear(call, decision)
    CallLatencyLog.record(
      @call_id,
      'branch_confirmed',
      turn_id: turn_id,
      extra: {
        kind: 'utterance',
        branch_id: decision.branch_id,
        recording_id: decision.recording_id,
        transfer: decision.transfer
      }
    )
    @after = after_action(decision)
    play(decision.recording_id, turn_id: turn_id, kind: 'utterance')
    remember_turn(call, text, decision)
    DialTransferService.start_operator!(call) if decision.transfer && @persist
  rescue => e
    Rails.logger.error("[BidirectionalCall] commit call_id=#{@call_id} error: #{e.message}")
    @busy = false
    @listening = true
  end

  def wait_for_stable
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + FINAL_WAIT_SEC
    loop do
      stable, extra, mono = snapshot
      return [stable, false, mono || Process.clock_gettime(Process::CLOCK_MONOTONIC)] if stable.present? && extra.blank?
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.02
    end
    stable, extra, mono = snapshot
    text = [stable, extra].reject(&:blank?).join
    [text, extra.present? || stable.blank?, mono || Process.clock_gettime(Process::CLOCK_MONOTONIC)]
  end

  def snapshot
    @lock.synchronize do
      stable = @finals.join
      extra = @interim.to_s
      extra = '' if extra.blank? || stable.end_with?(extra)
      [stable, extra, @final_mono]
    end
  end

  def start_preview
    text, = snapshot
    return if text.blank?
    return if @preview_text == text && (@preview_decision || @preview_thread&.alive?)

    @preview_text = text
    @preview_decision = nil
    gen = (@preview_gen += 1)
    confidence = @confidence
    @preview_thread = Thread.new do
      Rails.application.executor.wrap do
        decision = @decider.decide(text, call: current_call, stt_confidence: confidence)
        @lock.synchronize do
          if gen == @preview_gen && @preview_text == text
            @preview_decision = decision
          end
        end
      end
    end
  rescue => e
    Rails.logger.error("[BidirectionalCall] preview call_id=#{@call_id} error: #{e.message}")
  end

  def take_preview(text)
    @lock.synchronize do
      return nil unless @preview_text == text && @preview_decision

      @preview_decision
    end
  end

  def escalate_unclear(call, decision)
    return decision unless decision.ambiguous

    next_streak = call&.unknown_streak.to_i + 1
    return decision unless next_streak >= DialFlowEngine::MAX_UNKNOWN_STREAK
    return decision unless DialPlaybackCache.fetch(@script_id, 'フロントアウト')

    DialRealtimeDecider::Decision.new(
      branch_id: 'フロントアウト',
      recording_id: 'フロントアウト',
      transfer: false,
      path: decision.path,
      ambiguous: true
    )
  end

  def remember_turn(call, text, decision)
    return unless @persist && call&.persisted?

    if decision.ambiguous
      DialFlowEngine.note_unclear!(call, transcript: text, path: decision.path)
    else
      DialFlowEngine.note_clear!(call)
    end
    if decision.branch_id == 'faq' && decision.recording_id.to_s =~ /\Afaq-(\d+)\z/
      call.update(pending_faq_id: Regexp.last_match(1).to_i)
    end
    call.append_call_turn!('them', text, script: decision.branch_id)
    us_text = TwilioService.script_text(decision.branch_id, call)
    call.append_call_turn!('us', us_text, script: decision.branch_id) unless decision.transfer
    if decision.transfer
      call.append_call_turn!('us', DialTransferService::THANKS_TEXT, script: 'transfer')
    end
    call.remember_context!(them: text, script: decision.branch_id, us: us_text.to_s)
    call.save_selected_status!(decision.branch_id) if TwilioService.hangup_script?(decision.branch_id)
    DialTransferService.cancel_operator!(call) if TwilioService.hangup_script?(decision.branch_id)
  rescue => e
    Rails.logger.error("[BidirectionalCall] remember call_id=#{@call_id} error: #{e.message}")
  end

  def after_action(decision)
    return :transfer if decision.transfer
    return :hangup if TwilioService.hangup_script?(decision.branch_id)

    :listen
  end

  def play(recording_id, turn_id:, kind:)
    bytes = DialPlaybackCache.fetch(@script_id, recording_id)
    if bytes.nil? || bytes.bytesize.zero?
      CallLatencyLog.record(
        @call_id,
        'audio_cache_miss',
        turn_id: turn_id,
        extra: { kind: kind, recording_id: recording_id.to_s }
      )
      arm_listen
      return
    end

    frames = []
    offset = 0
    while offset < bytes.bytesize
      frames << bytes.byteslice(offset, 160)
      offset += 160
    end
    @playing = true
    @listening = false
    @play_gen += 1
    gen = @play_gen
    send_media(frames.first)
    if turn_id
      CallLatencyLog.record(
        @call_id,
        'audio_first_sent',
        turn_id: turn_id,
        extra: { kind: kind, recording_id: recording_id.to_s }
      )
    end
    send_mark("turn-#{turn_id}-first") if turn_id
    @play_thread = Thread.new do
      frames.drop(1).each do |frame|
        break if gen != @play_gen
        sleep 0.02
        break if gen != @play_gen

        send_media(frame)
      end
      sleep 0.02 if gen == @play_gen
      finish_playback(gen, recording_id) if gen == @play_gen
    end
  end

  def finish_playback(gen, recording_id)
    return if gen != @play_gen

    @playing = false
    action = @after
    @after = nil
    case action
    when :hangup
      CallRedirector.new.redirect_handoff(@call_sid, @call_id, recording_id, hangup: true)
    when :transfer
      CallRedirector.new.redirect_handoff(@call_sid, @call_id, 'transfer', hangup: false)
    else
      arm_listen
    end
  rescue => e
    Rails.logger.error("[BidirectionalCall] playback done call_id=#{@call_id} error: #{e.message}")
    arm_listen
  end

  def arm_listen
    @busy = false
    @playing = false
    @listening = true
    @vad.reset
    @barge_ms = 0
    @quiet_since = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @lock.synchronize do
      @finals.clear
      @interim = ''
      @final_mono = nil
      @preview_text = nil
      @preview_decision = nil
    end
  end

  def note_barge(mulaw_bytes)
    @barge_vad ||= UtteranceVad.new
    offset = 0
    while offset < mulaw_bytes.bytesize
      frame = mulaw_bytes.byteslice(offset, 160)
      offset += 160
      if @barge_vad.voiced_frame?(frame)
        @barge_ms += 20
      else
        @barge_ms = 0
      end
      next if @barge_ms < BARGE_MS

      @play_gen += 1
      @playing = false
      send_clear
      @vad.reset
      @vad.arm_from_barge
      @listening = true
      @busy = false
      @barge_ms = 0
      break
    end
  end

  def note_quiet
    return if @vad.in_speech?

    now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @quiet_since ||= now
    return if now - @quiet_since < LISTEN_TIMEOUT_SEC

    @quiet_since = now
    on_timeout
  end

  def on_timeout
    return if @busy || @playing

    @busy = true
    @listening = false
    @turn += 1
    turn_id = @turn
    CallLatencyLog.record(@call_id, 'utterance_end', turn_id: turn_id, extra: { kind: 'timeout' })
    call = current_call
    key = call ? DialFlowEngine.on_listen_timeout(call) : 'clarify'
    CallLatencyLog.record(@call_id, 'branch_confirmed', turn_id: turn_id, extra: { kind: 'timeout', branch_id: key })
    @after = TwilioService.hangup_script?(key) ? :hangup : :listen
    play(key, turn_id: turn_id, kind: 'timeout')
  rescue => e
    Rails.logger.error("[BidirectionalCall] timeout call_id=#{@call_id} error: #{e.message}")
    arm_listen
  end

  def current_call
    return @call unless @persist

    found = Call.find_by(id: @call_id)
    @script_id = found.dial_script_id if found
    found || @call
  end

  def broadcast(text, status)
    CallTranscriptBroadcaster.broadcast(
      @call_id,
      speaker: 'them',
      text: text,
      interim: status == 'interim',
      status: status
    )
  rescue => e
    Rails.logger.error("[BidirectionalCall] broadcast call_id=#{@call_id} error: #{e.message}")
  end

  def send_media(frame)
    send_json(
      'event' => 'media',
      'streamSid' => @stream_sid,
      'media' => { 'payload' => Base64.strict_encode64(frame.to_s) }
    )
  end

  def send_mark(name)
    send_json('event' => 'mark', 'streamSid' => @stream_sid, 'mark' => { 'name' => name })
  end

  def send_clear
    send_json('event' => 'clear', 'streamSid' => @stream_sid)
  end

  def send_json(payload)
    @send_lock.synchronize { @ws.send(JSON.generate(payload)) }
  rescue => e
    Rails.logger.error("[BidirectionalCall] send call_id=#{@call_id} error: #{e.message}")
  end
end
