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
  # Google の認識結果は話し終わりから遅れて届く（実測 0.5〜3 秒。通話の最初は特に遅い）
  LATE_TEXT_WAIT_SEC = 2.0  # 文字がまだ1つも届いていないとき、待つ上限
  FINAL_RECHECK_SEC = 1.5   # 途中結果で「不明」になったとき、確定結果を待って判定し直す上限
  BARGE_MS = 200

  # 待ち時間（秒）。docs/auto_dial_cursor_prompts.md の共通仕様。
  TIMING = {
    greet_wait: 1.5,   # 接続後、相手が名乗らないときに挨拶を始めるまで
    silence_step: 2.5, # こちらが話した後の無言1段階
    hold_max: 60,      # 保留に入ってから、人の返事がないまま切るまで
    watchdog: 10,      # 保留以外で、こちらが何も流していない上限
    tick: 0.5,         # 見張りの確認間隔
    play_margin: 1.5   # 再生終わりの合図（mark）が届かないときに、録音の長さ＋この秒数で終わったとみなす
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
    # Twilio が録音を最後まで流し終えた合図
    if (gen = name.to_s[/\Aplay-(\d+)-end\z/, 1])
      finish_playback(gen.to_i, @playing_id) if gen.to_i == @play_gen && @playing
      return
    end

    turn_id = name.to_s[/turn-(\d+)-first/, 1]
    return if turn_id.blank?

    CallLatencyLog.record(
      @call_id,
      'playback_mark',
      turn_id: turn_id.to_i,
      extra: { kind: 'utterance', name: name.to_s }
    )
  end

  # 音声認識が落ちたとき。相手の声が一切わからないまま話すと会話が壊れるので、
  # 何も流さずに切る（結果は付けない。システム側の失敗のため）。
  def on_error(error)
    return if @closed || %i[transfer ended].include?(@phase)

    log_event('stt_error', message: error.respond_to?(:message) ? error.message.to_s[0, 200] : error.to_s[0, 200])
    hangup_silently!('stt_error')
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
    @last_output_at = now # 見張りは「相手が話し終えてから」数え直す
    @turn += 1
    turn_id = @turn
    gen = (@turn_gen += 1)
    log_event('utterance_end', turn_id: turn_id, kind: 'utterance')
    start_preview
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

    # 第一声のあとは文字を待たずにすぐ挨拶する（留守電かどうかは挨拶しながら確かめる）
    if @phase == :opening
      call = current_call
      return commit_opening(turn_id, call, text, doubt)
    end

    if text.blank?
      text, doubt = wait_for_text(LATE_TEXT_WAIT_SEC)
      return if stale?(gen)
      log_event('late_text', turn_id: turn_id, text: text.to_s) if text.present?
    end

    # 言葉が取れなかった音（雑音・保留音）は、発話ではなく無音として扱う
    if text.blank?
      case @phase
      when :hold then return ignore_turn(turn_id, 'blank')
      when :opening then return start_greeting(turn_id)
      else return on_silence(turn_id, reason: 'blank')
      end
    end

    call = current_call
    decision = decide_turn(text, call, doubt)
    return if stale?(gen)

    text, decision = recheck_with_final(turn_id, call, text, decision) if doubt && decision.ambiguous
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

  # 文字が届くまで待つ（届いた分をつなげて返す）
  def wait_for_text(seconds)
    deadline = now + seconds
    loop do
      stable, extra, = snapshot
      text = [stable, extra].reject(&:blank?).join
      return [text, stable.blank? || extra.present?] if text.present?
      return ['', true] if now >= deadline || @closed

      sleep 0.05
    end
  end

  # 途中結果（例:「はい、私です」の途中の「私」）で判定すると誤るため、
  # 「不明」になったときだけ確定結果を待って判定し直す
  def recheck_with_final(turn_id, call, text, decision)
    deadline = now + FINAL_RECHECK_SEC
    final = nil
    before, = snapshot
    loop do
      stable, = snapshot
      if stable.present? && stable != before
        final = stable
        break
      end
      break if now >= deadline || @closed

      sleep 0.05
    end
    return [text, decision] if final.nil? || final == text

    redo_decision = @decider.decide(final, call: call, stt_confidence: @confidence)
    log_event('final_recheck', turn_id: turn_id, text: final, branch_id: redo_decision.branch_id)
    [final, redo_decision]
  end

  def stale?(gen)
    @closed || gen != @turn_gen || !%i[opening talk hold].include?(@phase)
  end

  def decide_turn(text, call, doubt)
    preview_thread = @preview_thread
    if preview_thread&.alive? && @preview_text == text
      preview_thread.join(PREVIEW_WAIT_SEC)
    end
    # 確定前の途中結果（interim）しか届いていなくても、文字が取れていれば十分使える。
    # 以前は 0.3 を渡して「聞き取りが怪しい」扱いにしており、AI に聞く前に必ず聞き返していた。
    take_preview(text) || @decider.decide(text, call: call, stt_confidence: doubt ? nil : @confidence)
  end

  # 第一声のあとは判定を待たずにすぐ挨拶する。
  # 判定が留守電・自動音声だったら、挨拶を止めて何も残さずに切る。
  def commit_opening(turn_id, call, text, doubt)
    start_greeting(turn_id)
    if text.blank?
      text, doubt = wait_for_text(LATE_TEXT_WAIT_SEC)
      log_event('late_text', turn_id: turn_id, text: text.to_s) if text.present?
      return if text.blank?
    end
    if @persist && call&.persisted?
      call.append_call_turn!('them', text, script: 'opening')
    end
    decision = decide_turn(text, call, doubt)
    text, decision = recheck_with_final(turn_id, call, text, decision) if doubt && !OPENING_REACT_KEYS.include?(decision.branch_id)
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
    # 挨拶の途中で相手が名乗った・話し出した場合は、聞き返さずに挨拶を言い直す
    if @greeting_interrupted
      @greeting_interrupted = false
      if decision.ambiguous || decision.branch_id == 'smalltalk'
        log_event('greeting_retry', turn_id: turn_id, text: text)
        @after = :listen
        return play('greeting', turn_id: turn_id, kind: 'greeting')
      end
    end
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
    # DB への書き込みは音声の処理と別スレッドで（DB が混んでいると音声の送受信が止まるため）
    Thread.new { Rails.application.executor.wrap { record_us(key, status: key == 'callback') } } if @persist
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
      if @listening && @vad.speaking? # 相手が話している間は止まっていない
        @last_output_at = t
        return
      end
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

  # 確定結果（final）が届いたとき、または話し終わった瞬間に、先に AI の判定を始めておく。
  # 確定結果は話し終わりから遅れて届くことが多いため、話し終わりの時点の途中結果でも始める。
  def start_preview
    stable, extra, = snapshot
    text = [stable, extra].reject(&:blank?).join
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

    @playing = true
    @listening = false
    @play_gen += 1
    @last_output_at = now
    gen = @play_gen
    send_media(bytes.byteslice(0, 160))
    if turn_id
      CallLatencyLog.record(
        @call_id,
        'audio_first_sent',
        turn_id: turn_id,
        extra: { kind: kind, recording_id: recording_id.to_s }
      )
    end
    send_mark("turn-#{turn_id}-first") if turn_id
    # 録音はまとめて送る。Twilio が受け取った順に実時間で流す。
    # 以前は 20 ミリ秒ずつ待ちながら送っていたが、待ちの誤差が積み重なって
    # 実時間より遅れ（音の途切れ）、再生の終わりも実際より遅く判断していた。
    @playing_id = recording_id
    rest = bytes.byteslice(160, bytes.bytesize - 160).to_s
    @play_thread = Thread.new do
      # 0.1 秒分ずつ送る（1フレームずつだと送る回数が多く、混んでいるときに途切れる）
      offset = 0
      while offset < rest.bytesize
        break if gen != @play_gen

        send_media(rest.byteslice(offset, 800))
        offset += 800
      end
      send_mark("play-#{gen}-end") if gen == @play_gen
      # 合図が届かない場合の保険
      sleep(bytes.bytesize / 8000.0 + @timing[:play_margin])
      finish_playback(gen, recording_id) if gen == @play_gen && @playing
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
    @lock.synchronize do
      return if gen != @play_gen || @finished_gen == gen

      @finished_gen = gen
    end

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
      @greeting_interrupted = true if @playing_id == 'greeting'
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
