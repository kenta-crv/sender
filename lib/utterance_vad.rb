require_relative 'mulaw'

# 相手の音声が途切れた時刻を、こちら側の無音時間で決める。
class UtteranceVad
  FRAME_BYTES = 160
  HANGOVER_MS = 500
  MIN_SPEECH_MS = 160
  # 雑音や保留音で話し中のまま抜けられなくなるのを防ぐ上限。
  MAX_UTTERANCE_MS = 8000

  attr_reader :forced

  def initialize(max_utterance_ms: MAX_UTTERANCE_MS)
    @max_utterance_ms = max_utterance_ms
    reset
  end

  def reset
    @speech_ms = 0
    @silence_ms = 0
    @in_speech = false
    @ended = false
    @forced = false
    @utterance_ms = 0
    @noise = nil
  end

  def arm_from_barge
    @in_speech = true
    @speech_ms = MIN_SPEECH_MS
    @silence_ms = 0
    @utterance_ms = MIN_SPEECH_MS
    @ended = false
    @forced = false
  end

  def ended?
    @ended
  end

  def in_speech?
    @in_speech
  end

  # 話し始めの短い音も含めて、いま声が出ているか
  def speaking?
    !@ended && (@in_speech || @speech_ms.positive?)
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
      if @in_speech
        @utterance_ms += ms
        if @utterance_ms >= @max_utterance_ms
          @ended = true
          @forced = true
          return true
        end
      end
      @speech_ms += ms
      @silence_ms = 0
      if !@in_speech && @speech_ms >= MIN_SPEECH_MS
        @in_speech = true
        @utterance_ms = @speech_ms
      end
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
