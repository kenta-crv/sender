require_relative 'mulaw'

# 相手の音声が途切れた時刻を、こちら側の無音時間で決める。
class UtteranceVad
  FRAME_BYTES = 160
  HANGOVER_MS = 320
  MIN_SPEECH_MS = 160

  def initialize
    reset
  end

  def reset
    @speech_ms = 0
    @silence_ms = 0
    @in_speech = false
    @ended = false
    @noise = nil
  end

  def arm_from_barge
    @in_speech = true
    @speech_ms = MIN_SPEECH_MS
    @silence_ms = 0
    @ended = false
  end

  def ended?
    @ended
  end

  def in_speech?
    @in_speech
  end

  # 発話終了を検知したら true。
  def feed(mulaw_bytes)
    return false if @ended || mulaw_bytes.nil? || mulaw_bytes.empty?

    offset = 0
    while offset < mulaw_bytes.bytesize
      frame = mulaw_bytes.byteslice(offset, FRAME_BYTES)
      offset += FRAME_BYTES
      return true if feed_frame(frame)
    end
    false
  end

  def voiced_frame?(frame)
    voiced?(frame)
  end

  private

  def feed_frame(frame)
    ms = frame.bytesize * 20.0 / FRAME_BYTES
    if voiced?(frame)
      @speech_ms += ms
      @silence_ms = 0
      @in_speech = true if @speech_ms >= MIN_SPEECH_MS
      false
    elsif @in_speech
      @silence_ms += ms
      if @silence_ms >= HANGOVER_MS
        @ended = true
        true
      else
        false
      end
    else
      @speech_ms = 0
      false
    end
  end

  def voiced?(frame)
    level = Mulaw.rms(frame)
    threshold = [@noise.to_f * 2.8, 450].max
    heard = level > threshold
    unless heard
      @noise = @noise.nil? ? level : (@noise * 0.95 + level * 0.05)
    end
    heard
  end
end
