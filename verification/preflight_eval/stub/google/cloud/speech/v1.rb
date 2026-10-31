# 点検のテスト用の偽物（本物の gem の代わり）
module Google; module Cloud; module Speech; module V1
  class RecognitionConfig
    module AudioEncoding; MULAW = :mulaw; end
    def initialize(**); end
  end
  module Speech
    class Client
      class << self; attr_accessor :behavior; end
      Conf = Struct.new(:credentials, :timeout)
      def initialize; yield Conf.new if block_given?; end
      Alt = Struct.new(:transcript); Res = Struct.new(:alternatives); Resp = Struct.new(:results)
      def recognize(config:, audio:)
        case self.class.behavior
        when :invalid_grant then raise "Authorization failed.  Server message:\n{\"error\":\"invalid_grant\",\"error_description\":\"Invalid JWT Signature.\"}"
        when :empty then Resp.new([])
        else Resp.new([Res.new([Alt.new('お電話が少し遠いようでして')])])
        end
      end
    end
  end
end; end; end; end
