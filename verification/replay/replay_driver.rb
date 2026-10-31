require 'json'
require 'base64'

# 電話をかけずに、本物の通話処理（MediaStreamHandler 以下すべて）へ受付役の声を流し込む。
# Twilio が送ってくるのと同じ形（20ミリ秒ごとの μ-law 音声）で、実時間で送る。
# 受付役は「こちらの録音が流れ終わったら、間をおいて次を話す」ように反応する。
class ReplayDriver
  FRAME = 160
  TICK = 0.02
  PLAY_END_GAP = 2.0 # 終わりの合図（mark）が来ないまま、こちらの音声がこの秒数途切れたら終わったとみなす

  Event = Struct.new(:data)
  Play = Struct.new(:key, :start, :finish, :cleared, keyword_init: true)

  class FakeWs
    def initialize(driver)
      @driver = driver
    end

    def send(json)
      @driver.on_outbound(json)
    end
  end

  attr_reader :timeline, :plays, :failures

  # handler:     MediaStreamHandler と同じく on_message(event) / on_close(event) を持つもの
  # recordings:  { 録音キー => μ-law バイト列 }（こちらが流した音声がどれかを当てるため）
  # noise_frame: 無音のときに送る 160 バイト（回線の雑音）を返す Proc
  def initialize(recordings:, noise_frame:, actions:)
    @recordings = recordings
    @noise_frame = noise_frame
    @actions = actions # 外部操作（切断・転送）の記録先。[[種類, 内容, 時刻], ...]
    @lock = Mutex.new
    @inbound = String.new(encoding: 'BINARY')
    @out = [] # Twilio 側の再生待ち（[:audio, bytes] / [:mark, name]）
    @cur = nil
    @plays = []
    @timeline = []
    @failures = []
  end

  def ws
    @ws ||= FakeWs.new(self)
  end

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def rel(t)
    (t - @t0).round(2)
  end

  def start(handler, call_id:, call_sid:, stream_sid:)
    @handler = handler
    @t0 = now
    @running = true
    send_event('event' => 'connected')
    send_event(
      'event' => 'start',
      'start' => {
        'callSid' => call_sid,
        'streamSid' => stream_sid,
        'customParameters' => { 'call_id' => call_id.to_s, 'phase' => 'talking', 'mode' => 'bidirectional' }
      }
    )
    @feeder = Thread.new { feed_loop(stream_sid) }
  end

  def stop
    @running = false
    @feeder&.join(2)
    finalize_play(force: true)
    send_event('event' => 'stop')
    @handler.on_close(nil)
  end

  # ---- 受付役の動き ----

  def say(text, audio)
    t = now
    @lock.synchronize { @inbound << audio }
    wait_until(audio.bytesize * TICK / FRAME + 5) { @lock.synchronize { @inbound.empty? } }
    @timeline << [t, :them, text]
  end

  def play_music(seconds, audio)
    @timeline << [now, :them, "（保留音 #{seconds}秒）"]
    @lock.synchronize { @inbound << audio }
    wait_until(seconds + 5) { @lock.synchronize { @inbound.empty? } }
  end

  def silence(seconds)
    @timeline << [now, :them, "（無言 #{seconds}秒）"]
    sleep seconds
  end

  # こちらの録音が新しく1つ流れ終わるまで待つ。流れなければ失敗として記録する。
  def wait_ours(gap:, timeout: 12, label: nil)
    seen = @plays.size
    ok = wait_until(timeout) { @plays.size > seen && @cur.nil? }
    unless ok
      @failures << "#{label || '返事'}: 相手が話し終えてから#{timeout}秒、こちらが何も流しませんでした"
      return false
    end
    sleep gap
    true
  end

  # 通話の終わり（切断・転送）を待つ
  def wait_end(timeout)
    wait_until(timeout) { ended? }
  end

  def ended?
    @actions.any? { |kind, _, _| %i[hangup transfer silent_hangup].include?(kind) }
  end

  # ---- Twilio 側（こちらが送った音声）----

  # Twilio と同じく、受け取った音声はためておき、実時間で流す。
  # mark は、その手前の音声を流し終えた時点でこちらへ返す。clear はためた音声を捨てる。
  def on_outbound(json)
    msg = JSON.parse(json)
    case msg['event']
    when 'media'
      bytes = Base64.decode64(msg.dig('media', 'payload').to_s)
      @lock.synchronize { @out << [:audio, bytes] }
    when 'mark'
      @lock.synchronize { @out << [:mark, msg.dig('mark', 'name').to_s] }
    when 'clear'
      @lock.synchronize { @out.clear }
      finalize_play(force: true, cleared: true)
    end
  end

  private

  def send_event(hash)
    @handler.on_message(Event.new(JSON.generate(hash)))
  end

  def feed_loop(stream_sid)
    next_at = now
    while @running
      frame = @lock.synchronize { @inbound.empty? ? nil : @inbound.slice!(0, FRAME) }
      frame = @noise_frame.call if frame.nil? || frame.bytesize < FRAME
      send_event(
        'event' => 'media',
        'streamSid' => stream_sid,
        'media' => { 'track' => 'inbound', 'payload' => Base64.strict_encode64(frame) }
      )
      play_tick(stream_sid)
      finalize_play
      next_at += TICK
      delay = next_at - now
      sleep delay if delay.positive?
    end
  rescue => e
    @failures << "送信処理のエラー: #{e.class}: #{e.message}"
  end

  # 20ミリ秒分の「こちらの音声」を流す
  def play_tick(stream_sid)
    marks = []
    @lock.synchronize do
      marks << @out.shift[1] while @out.first && @out.first[0] == :mark
      head = @out.first
      if head
        chunk = head[1].slice!(0, FRAME)
        @out.shift if head[1].empty?
        @cur ||= { start: now, bytes: String.new(encoding: 'BINARY') }
        @cur[:bytes] << chunk
        @cur[:last] = now
      end
      marks << @out.shift[1] while @out.first && @out.first[0] == :mark
    end
    marks.each do |name|
      finalize_play(force: true) if name.start_with?('play-')
      send_event('event' => 'mark', 'streamSid' => stream_sid, 'mark' => { 'name' => name })
    end
  end

  def finalize_play(force: false, cleared: false)
    cur = nil
    @lock.synchronize do
      return if @cur.nil?
      return unless force || now - @cur[:last] > PLAY_END_GAP

      cur = @cur
      @cur = nil
    end
    key = identify(cur[:bytes])
    @plays << Play.new(key: key, start: cur[:start], finish: cur[:last], cleared: cleared)
    @timeline << [cur[:start], :us, key + (cleared ? '（途中で止めた）' : '')]
  end

  def identify(bytes)
    exact = @recordings.find { |_k, b| b == bytes }
    return exact[0] if exact

    # 途中で止まった場合。先頭の無音だけでは、どの録音か区別できない
    prefix = @recordings.select { |_k, b| b.start_with?(bytes) }
    return prefix.keys.first if prefix.size == 1
    return 'partial' if prefix.size > 1

    'unknown'
  end

  def wait_until(timeout)
    deadline = now + timeout
    until yield
      return false if now > deadline

      sleep 0.05
    end
    true
  end
end
