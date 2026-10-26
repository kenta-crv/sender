require 'base64'
require 'json'
require_relative 'utterance_vad'

# 原稿ID 1 の双方向ストリーム。途中の認識では再生も転送もしない。
#
# 通話の段階（@phase）
#   :opening  接続直後。相手の第一声の終わりか、無音 greet_wait 秒を待って挨拶する
#   :talk     受付との会話
#   :hold     取り次ぎ中（保留）。何も話さず、本人・不在・断り・改めて だけに反応する
#   :transfer 担当者へ転送中
#   :ended    終了
class BidirectionalCallSession
  FINAL_WAIT_SEC = 0.4
  PREVIEW_WAIT_SEC = 2.0
  BARGE_MS = 200

  # 待ち時間（秒）。docs/auto_dial_cursor_prompts.md の共通仕様。
  TIMING = {
    greet_wait: 1.5,   # 接続後、相手が名乗らないときに挨拶を始めるまで
    silence_step: 2.5, # こちらが話した後の無言1段階
    hold_max: 60,      # 保留に入ってから、人の返事がないまま切るまで
    watchdog: 10,      # 保留以外で、こちらが何も流していない上限
    tick: 0.5          # 見張りの確認間隔
  }.freeze

  SILENCE_KEYS = %w[silence_1 silence_2 callback].freeze
  UNCLEAR_KEYS = %w[clarify clarify_simple callback].freeze
  HOLD_REACT_KEYS = %w[transfer 担当者不在 フロントアウト callback].freeze
  OPENING_REACT_KEYS = %w[着信不在 電話不通].freeze
  HOLD_TIMEOUT_STATUS = '担当者不在'.freeze

  attr_reader :phase

  def initialize(ws, call_id:, call_sid:, stream_sid:, call: nil, persist: true, greet: true,
                 decider: DialRealtimeDecider, timing: {}, hangup: nil, vad: nil)
    @ws = ws
    @call_id = call_id
    @call_sid = call_sid
    @stream_sid = stream_sid
    @call = call
    @persist = persist
    @greet = greet
    @decider = decider
    @timing = TIMING.merge(timing)
    @hangup = hangup || ->(sid) { TwilioService.new.hangup_call(sid) }
    @script_id = call&.dial_script_id
    @lock = Mutex.new
    @send_lock = Mutex.new
    @vad = vad || UtteranceVad.new
    @finals = []
    @interim = ''
    @final_mono = nil
    @confidence = nil
    @phase = greet ? :opening : :talk
    @listening = true
    @playing = false
    @play_gen = 0
    @busy = false
    @turn = 0
    @turn_gen = 0
    @preview_gen = 0
    @preview_text = nil
    @preview_decision = nil
    @barge_ms = 0
    @quiet_since = nil
    @after = nil
    @closed = false
    @silence_stage = 0
    @unclear_count = 0
    @hold_since = nil
    @last_output_at = now
  end

  def start!
    @quiet_since = now
    @last_output_at = now
    start_watchdog
  end

  def feed(mulaw_bytes)
    return if @closed || mulaw_bytes.nil? || mulaw_bytes.empty?

    if @playing
      # 切る前・転送前の録音は、相手の声で止めない
      note_barge(mulaw_bytes) if @after.nil? || @after == :listen
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
      @final_mono = now
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

  # 音声認識が落ちたとき。保留中は何もしない。
  def on_error(_error)
    return if @closed || @busy || @playing
    return unless %i[opening talk].include?(@phase)

    @busy = true
    @listening = false
    @turn += 1
    respond_unclear(@turn, current_call, '', path: 'stt_error')
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

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def log_event(event, turn_id: nil, **extra)
    CallLatencyLog.record(@call_id, event, turn_id: turn_id, extra: extra.merge(phase: @phase.to_s))
  end

  def on_utterance_end
    return if @busy

    forced = @vad.forced
    @busy = true
    @listening = false
    @quiet_since = nil
    @turn += 1
    turn_id = @turn
    gen = (@turn_gen += 1)
    log_event('utterance_end', turn_id: turn_id, kind: 'utterance')
    log_event('forced_cut', turn_id: turn_id) if forced
    @worker = Thread.new do
      Rails.application.executor.wrap { commit_turn(turn_id, gen) }
    end
  end

  def commit_turn(turn_id, gen)
    text, doubt, final_mono = wait_for_stable
    CallLatencyLog.record(
      @call_id,
      'transcript_final',
      turn_id: turn_id,
      at_mono: final_mono,
      extra: { kind: 'utterance', doubt: doubt, text: text.to_s, phase: @phase.to_s }
    )
    return if stale?(gen)

    # 言葉が取れなかった音（雑音・保留音）は、発話ではなく無音として扱う
    if text.blank?
      case @phase
      when :hold then return ignore_turn(turn_id, 'blank')
      when :opening then return start_greeting(turn_id)
      else return on_silence(turn_id, reason: 'blank')
      end
    end

    call = current_call
    return commit_opening(turn_id, call, text, doubt) if @phase == :opening

    decision = decide_turn(text, call, doubt)
    return if stale?(gen)

    case @phase
    when :hold then commit_hold(turn_id, call, text, decision)
    when :talk then commit_talk(turn_id, call, text, decision)
    end
  rescue => e
    Rails.logger.error("[BidirectionalCall] commit call_id=#{@call_id} error: #{e.message}")
    @busy = false
    @listening = true
  end

  def stale?(gen)
    @closed || gen != @turn_gen || !%i[opening talk hold].include?(@phase)
  end

  def decide_turn(text, call, doubt)
    preview_thread = @preview_thread
    if preview_thread&.alive? && @preview_text == text
      preview_thread.join(PREVIEW_WAIT_SEC)
    end
    take_preview(text) || @decider.decide(text, call: call, stt_confidence: doubt ? 0.3 : @confidence)
  end

  # 第一声のあとは判定を待たずにすぐ挨拶する。
  # 判定が留守電・自動音声だったら、挨拶を止めて何も残さずに切る。
  def commit_opening(turn_id, call, text, doubt)
    if @persist && call&.persisted?
      call.append_call_turn!('them', text, script: 'opening')
    end
    start_greeting(turn_id)
    decision = decide_turn(text, call, doubt)
    return unless OPENING_REACT_KEYS.include?(decision.branch_id)
    return if @closed || %i[transfer ended].include?(@phase)

    log_event('opening_machine', turn_id: turn_id, branch_id: decision.branch_id)
    hangup_silently!('opening_machine', status: decision.branch_id)
  end

  def commit_hold(turn_id, call, text, decision)
    if HOLD_REACT_KEYS.include?(decision.branch_id)
      log_event('hold_end', turn_id: turn_id, branch_id: decision.branch_id)
      @phase = :talk
      @unclear_count = 0
      @silence_stage = 0
      return act(turn_id, call, text, decision)
    end

    if decision.branch_id == 'wait'
      # 「もう少々お待ちください」など。人がいるので保留の時間を延ばす
      @hold_since = now
      return ignore_turn(turn_id, 'hold_wait', text: text)
    end

    ignore_turn(turn_id, 'hold_ignored', text: text, branch_id: decision.branch_id)
  end

  def commit_talk(turn_id, call, text, decision)
    @silence_stage = 0
    return respond_unclear(turn_id, call, text, path: decision.path) if decision.ambiguous

    @unclear_count = 0
    if decision.branch_id == 'wait'
      @phase = :hold
      @hold_since = now
      log_event('hold_start', turn_id: turn_id)
    end
    act(turn_id, call, text, decision)
  end

  # 聞き取れないとき: 1回目 clarify → 2回目 clarify_simple → 3回目 callback で切る
  def respond_unclear(turn_id, call, text, path:)
    @unclear_count += 1
    key = UNCLEAR_KEYS[[@unclear_count, UNCLEAR_KEYS.size].min - 1]
    log_event('unclear_step', turn_id: turn_id, count: @unclear_count, recording_id: key, path: path.to_s)
    decision = DialRealtimeDecider::Decision.new(
      branch_id: key,
      recording_id: key,
      transfer: false,
      path: path,
      ambiguous: true
    )
    act(turn_id, call, text, decision)
  end

  def act(turn_id, call, text, decision)
    CallLatencyLog.record(
      @call_id,
      'branch_confirmed',
      turn_id: turn_id,
      extra: {
        kind: 'utterance',
        phase: @phase.to_s,
        branch_id: decision.branch_id,
        recording_id: decision.recording_id,
        transfer: decision.transfer
      }
    )
    @after = after_action(decision)
    @phase = :transfer if decision.transfer
    play(decision.recording_id, turn_id: turn_id, kind: 'utterance')
    remember_turn(call, text, decision)
    DialTransferService.start_operator!(call) if decision.transfer && @persist
  end

  def ignore_turn(turn_id, reason, **extra)
    log_event('turn_ignored', turn_id: turn_id, reason: reason, **extra)
    arm_listen
  end

  def start_greeting(turn_id)
    return unless @phase == :opening

    @phase = :talk
    @after = :listen
    play('greeting', turn_id: turn_id, kind: 'greeting')
  end

  # 無言のとき: silence_1（もしもし）→ silence_2（電話が遠い）→ callback で切る
  def on_silence(turn_id, reason:)
    return if @closed || @playing || @phase != :talk

    @busy = true
    @listening = false
    turn_id ||= (@turn += 1)
    @silence_stage += 1
    key = SILENCE_KEYS[[@silence_stage, SILENCE_KEYS.size].min - 1]
    log_event('silence_step', turn_id: turn_id, stage: @silence_stage, reason: reason.to_s, recording_id: key)
    @after = TwilioService.hangup_script?(key) ? :hangup : :listen
    play(key, turn_id: turn_id, kind: 'silence')
    record_us(key, status: key == 'callback')
  end

  def record_us(key, status: false)
    return unless @persist

    call = current_call
    return unless call&.persisted?

    call.append_call_turn!('us', TwilioService.script_text(key, call), script: key)
    return unless status

    call.save_selected_status!(key)
    DialTransferService.cancel_operator!(call)
  rescue => e
    Rails.logger.error("[BidirectionalCall] record_us call_id=#{@call_id} error: #{e.message}")
  end

  # 何も流さずに切る（保留60秒・録音が無いとき）
  def hangup_silently!(reason, status: nil)
    return if @closed || @phase == :ended

    @phase = :ended
    log_event('silent_hangup', reason: reason.to_s)
    @play_gen += 1
    @playing = false
    @listening = false
    if @persist
      call = current_call
      if call&.persisted?
        call.save_selected_status!(status) if status
        DialTransferService.cancel_operator!(call)
      end
    end
    @hangup.call(@call_sid)
    finish
  rescue => e
    Rails.logger.error("[BidirectionalCall] silent hangup call_id=#{@call_id} error: #{e.message}")
    finish
  end

  def start_watchdog
    return if @watchdog&.alive?

    @watchdog = Thread.new do
      until @closed
        sleep @timing[:tick]
        begin
          watchdog_tick
        rescue => e
          Rails.logger.error("[BidirectionalCall] watchdog call_id=#{@call_id} error: #{e.message}")
        end
      end
    end
  end

  def watchdog_tick
    return if @closed

    t = now
    case @phase
    when :hold
      return if @playing || @hold_since.nil?
      return if t - @hold_since < @timing[:hold_max]

      hangup_silently!('hold_timeout', status: HOLD_TIMEOUT_STATUS)
    when :opening, :talk
      return if @playing
      return if t - @last_output_at < @timing[:watchdog]

      log_event('watchdog', idle_sec: (t - @last_output_at).round(1))
      @turn_gen += 1 # 止まっている判定の結果は捨てる
      @busy = false
      if @phase == :opening
        start_greeting(nil)
      else
        on_silence(nil, reason: 'watchdog')
      end
    end
  end

  def wait_for_stable
    deadline = now + FINAL_WAIT_SEC
    loop do
      stable, extra, mono = snapshot
      return [stable, false, mono || now] if stable.present? && extra.blank?
      break if now >= deadline

      sleep 0.02
    end
    stable, extra, mono = snapshot
    text = [stable, extra].reject(&:blank?).join
    [text, extra.present? || stable.blank?, mono || now]
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
    call.append_call_turn!('them', text, script: decision.branch_id) if text.present?
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

  def cached?(recording_id)
    bytes = DialPlaybackCache.fetch(@script_id, recording_id)
    !bytes.nil? && bytes.bytesize.positive?
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
      play_fallback(recording_id, turn_id: turn_id, kind: kind)
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
    @last_output_at = now
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

  # 流す録音が無いとき。黙って聞く状態には戻さない。
  def play_fallback(missing, turn_id:, kind:)
    case @after
    when :transfer
      @after = nil
      CallRedirector.new.redirect_handoff(@call_sid, @call_id, 'transfer', hangup: false)
    when :hangup
      if missing.to_s != 'callback' && cached?('callback')
        play('callback', turn_id: turn_id, kind: kind)
      else
        hangup_silently!('audio_missing')
      end
    else
      fallback = %w[clarify callback].find { |key| key != missing.to_s && cached?(key) }
      if fallback.nil?
        hangup_silently!('audio_missing')
      else
        @after = :hangup if fallback == 'callback'
        play(fallback, turn_id: turn_id, kind: kind)
      end
    end
  end

  def finish_playback(gen, recording_id)
    return if gen != @play_gen

    @playing = false
    @last_output_at = now
    action = @after
    @after = nil
    case action
    when :hangup
      @phase = :ended
      CallRedirector.new.redirect_handoff(@call_sid, @call_id, recording_id, hangup: true)
    when :transfer
      @phase = :transfer
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
    @quiet_since = now
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
      @last_output_at = now
      send_clear
      @vad.reset
      @vad.arm_from_barge
      @listening = true
      @busy = false
      @barge_ms = 0
      break
    end
  end

  # 無音の時間で、挨拶と無言の段階を進める（保留中は見張りが60秒を見る）
  def note_quiet
    return if @vad.speaking? || @busy

    t = now
    @quiet_since ||= t
    quiet = t - @quiet_since
    case @phase
    when :opening
      return if quiet < @timing[:greet_wait]

      @quiet_since = t
      start_greeting(nil)
    when :talk
      return if quiet < @timing[:silence_step]

      @quiet_since = t
      on_silence(nil, reason: 'quiet')
    end
  rescue => e
    Rails.logger.error("[BidirectionalCall] quiet call_id=#{@call_id} error: #{e.message}")
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
