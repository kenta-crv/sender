# frozen_string_literal: true

# macOS環境でのSSL証明書CRL検証エラー回避
# webdrivers gemがChromeDriverダウンロード時にSSLエラーを起こす問題への対策
# webdrivers gemは use_ssl= の後に verify_mode = VERIFY_PEER を再設定するため、
# verify_mode= 自体をオーバーライドする必要がある

require 'openssl'
require 'net/http'

module Net
  class HTTP
    alias_method :original_verify_mode=, :verify_mode=
    def verify_mode=(_mode)
      self.original_verify_mode = OpenSSL::SSL::VERIFY_NONE
    end
  end
end
