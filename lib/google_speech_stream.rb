require 'google/cloud/speech/v1'

class GoogleSpeechStream
  def initialize(call_id:, hints: [], on_result:, on_error: nil)
    @call_id = call_id
    @hints = hints
    @on_result = on_result
    @on_error = on_error || ->(e) { Rails.logger.error("[GoogleSpeech] call_id=#{call_id} error: #{e.message}") }
    @audio_queue = Queue.new
    @running = false
  end

  def start
    @running = true
    @reader_thread = Thread.new { run_streaming }
  rescue => e
    @on_error.call(e)
  end

  def feed_audio(raw_bytes)
    return unless @running
    @audio_queue.push(raw_bytes)
  end

  def stop
    @running = false
    @audio_queue.push(:stop)
    @reader_thread&.join(5)
  rescue => e
    Rails.logger.warn("[GoogleSpeech] stop error: #{e.message}")
  end

  private

  def run_streaming
    client = Google::Cloud::Speech::V1::Speech::Client.new

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
      interim_results: false,
      single_utterance: false
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
        next unless result.is_final

        transcript = result.alternatives.first&.transcript
        confidence = result.alternatives.first&.confidence
        next if transcript.nil? || transcript.empty?

        Rails.logger.info("[GoogleSpeech] call_id=#{@call_id} FINAL: '#{transcript}' (#{confidence})")
        @on_result.call(transcript, confidence)
      end
    end

  rescue => e
    @on_error.call(e)
  end
end
