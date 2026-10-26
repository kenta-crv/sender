require 'google/cloud/speech/v1'
require_relative 'mulaw'

class GoogleSpeechStream
  # 声がある区間だけ Google に送る（無音・再生中の静寂は課金対象にしない）
  FRAME_BYTES = 160
  MIN_SPEECH_MS = 60
  HANGOVER_MS = 400
  PRE_ROLL_FRAMES = 5
  NOISE_FLOOR = 450
  NOISE_RATIO = 2.8

  def initialize(call_id:, hints: [], single_utterance: false, on_result:, on_error: nil, on_interim: nil, interim_any: false)
    @call_id = call_id
    @hints = hints
    @single_utterance = single_utterance
    @on_result = on_result
    @on_interim = on_interim
    @on_error = on_error || ->(e) { Rails.logger.error("[GoogleSpeech] call_id=#{call_id} error: #{e.message}") }
    @audio_queue = Queue.new
    @running = false
    @interim_any = interim_any
    reset_send_gate
  end

  def start
    @running = true
    reset_send_gate
    @reader_thread = Thread.new { run_streaming }
  rescue => e
    @on_error.call(e)
  end

  def feed_audio(raw_bytes)
    return unless @running
    return if raw_bytes.nil? || raw_bytes.empty?

    keep = String.new(encoding: 'ASCII-8BIT')
    offset = 0
    while offset < raw_bytes.bytesize
      frame = raw_bytes.byteslice(offset, FRAME_BYTES)
      offset += FRAME_BYTES
      append_gated_frame(keep, frame)
    end
    return if keep.empty?

    @audio_queue.push(keep)
  end

  def stop
    @running = false
    @audio_queue.push(:stop)
    @reader_thread&.join(5)
  rescue => e
    Rails.logger.warn("[GoogleSpeech] stop error: #{e.message}")
  end

  private

  def reset_send_gate
    @send_open = false
    @send_speech_ms = 0
    @send_silence_ms = 0
    @send_noise = nil
    @pre_roll = []
  end

  # 声の立ち上がり〜余韻だけ keep に積む。無音は捨てる。
  def append_gated_frame(keep, frame)
    ms = frame.bytesize * 20.0 / FRAME_BYTES
    if voiced_frame?(frame)
      @send_speech_ms += ms
      @send_silence_ms = 0
      unless @send_open
        if @send_speech_ms >= MIN_SPEECH_MS
          @send_open = true
          keep << @pre_roll.join
          @pre_roll.clear
          keep << frame
          log_gate('open')
        else
          push_pre_roll(frame)
        end
        return
      end
      keep << frame
    elsif @send_open
      @send_silence_ms += ms
      if @send_silence_ms >= HANGOVER_MS
        @send_open = false
        @send_speech_ms = 0
        @send_silence_ms = 0
        @pre_roll.clear
        log_gate('close')
      else
        keep << frame
      end
    else
      @send_speech_ms = 0
      push_pre_roll(frame)
    end
  end

  def push_pre_roll(frame)
    @pre_roll << frame
    @pre_roll.shift while @pre_roll.size > PRE_ROLL_FRAMES
  end

  def voiced_frame?(frame)
    level = Mulaw.rms(frame)
    threshold = [@send_noise.to_f * NOISE_RATIO, NOISE_FLOOR].max
    heard = level > threshold
    unless heard
      @send_noise = @send_noise.nil? ? level : (@send_noise * 0.95 + level * 0.05)
    end
    heard
  end

  def log_gate(state)
    return unless defined?(Rails)

    Rails.logger.debug("[GoogleSpeech] call_id=#{@call_id} send_gate #{state}")
  end

  def run_streaming
    client = Google::Cloud::Speech::V1::Speech::Client.new do |config|
      path = ENV['GOOGLE_APPLICATION_CREDENTIALS']
      config.credentials = path if path.present? && File.exist?(path)
    end

    # ストリーミング設定
    config = Google::Cloud::Speech::V1::RecognitionConfig.new(
      encoding: Google::Cloud::Speech::V1::RecognitionConfig::AudioEncoding::MULAW,
      sample_rate_hertz: 8000,
      language_code: 'ja-JP',
      model: 'phone_call',
      speech_contexts: [
        Google::Cloud::Speech::V1::SpeechContext.new(phrases: @hints)
      ]
    )

    streaming_config = Google::Cloud::Speech::V1::StreamingRecognitionConfig.new(
      config: config,
      interim_results: true,
      single_utterance: @single_utterance
    )

    # 音声チャンクを生成するEnumerator
    audio_enum = Enumerator.new do |yielder|
      # 最初のリクエストは設定のみ
      yielder << Google::Cloud::Speech::V1::StreamingRecognizeRequest.new(
        streaming_config: streaming_config
      )

      # 音声チャンクを送信
      buffer = String.new(encoding: 'ASCII-8BIT')
      while @running
        chunk = @audio_queue.pop
        break if chunk == :stop

        buffer << chunk

        # 100ms分（800バイト @ 8kHz mulaw）ごとにまとめて送信
        if buffer.bytesize >= 800
          yielder << Google::Cloud::Speech::V1::StreamingRecognizeRequest.new(
            audio_content: buffer
          )
          buffer = String.new(encoding: 'ASCII-8BIT')
        end
      end

      # 残りのバッファを送信
      if buffer.bytesize > 0
        yielder << Google::Cloud::Speech::V1::StreamingRecognizeRequest.new(
          audio_content: buffer
        )
      end
    end

    # ストリーミング認識実行
    responses = client.streaming_recognize(audio_enum)

    responses.each do |response|
      next unless response.results&.any?

      response.results.each do |result|
        transcript = result.alternatives.first&.transcript
        confidence = result.alternatives.first&.confidence || 0.0
        next if transcript.nil? || transcript.empty?

        if result.is_final
          Rails.logger.info("[GoogleSpeech] call_id=#{@call_id} FINAL: '#{transcript}' (#{confidence})")
          @on_result.call(transcript, confidence)
        elsif @on_interim
          @on_interim.call(transcript, confidence)
        end
      end
    end

  rescue => e
    @on_error.call(e)
  end
end
