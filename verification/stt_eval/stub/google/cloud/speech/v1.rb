# GoogleSpeechStream のテスト用の偽物。$stt_plan の順に、接続ごとの振る舞いを決める。
module Google; module Cloud; module Speech; module V1
  class RecognitionConfig; module AudioEncoding; MULAW = 1; end; def initialize(**); end; end
  class SpeechContext; def initialize(**); end; end
  class StreamingRecognitionConfig; def initialize(**); end; end
  class StreamingRecognizeRequest
    attr_reader :audio_content
    def initialize(streaming_config: nil, audio_content: nil); @audio_content = audio_content; end
  end
  module Speech
    class Client
      Alt = Struct.new(:transcript, :confidence); Res = Struct.new(:alternatives, :is_final); Resp = Struct.new(:results)
      def initialize; yield Struct.new(:credentials).new if block_given?; end
      def streaming_recognize(enum)
        plan = $stt_plan.shift || :normal
        $stt_connections += 1
        Enumerator.new do |y|
          got = 0
          enum.each do |req|
            next unless req.audio_content
            $stt_bytes += req.audio_content.bytesize
            got += 1
            raise 'Audio Timeout Error: Long duration elapsed without audio.' if plan == :timeout && got >= 2
            raise 'Authorization failed. invalid_grant' if plan == :auth
            if plan == :normal && got == 3
              y << Resp.new([Res.new([Alt.new('もしもし', 0.9)], true)])
            end
            break if plan == :end && got >= 2
          end
        end
      end
    end
  end
end; end; end; end
