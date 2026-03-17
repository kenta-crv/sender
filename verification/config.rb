# frozen_string_literal: true

module Config
  # Twilio認証情報（環境変数から取得）
  TWILIO_ACCOUNT_SID = ENV.fetch("TWILIO_ACCOUNT_SID")
  TWILIO_AUTH_TOKEN  = ENV.fetch("TWILIO_AUTH_TOKEN")

  # Twilio発信元番号
  TWILIO_FROM_NUMBER = ENV.fetch("TWILIO_FROM_NUMBER")

  # テスト用電話番号（発信先）
  TEST_TO_NUMBER = ENV.fetch("TEST_TO_NUMBER")

  # オペレーター番号（転送先）
  OPERATOR_NUMBER = ENV.fetch("OPERATOR_NUMBER")

  # ngrok URL（ngrok起動後に設定）
  NGROK_URL = ENV.fetch("NGROK_URL")

  # Sinatra サーバーポート
  PORT = 4567
end
