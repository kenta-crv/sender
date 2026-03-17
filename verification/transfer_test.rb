# frozen_string_literal: true

# 転送遅延テスト用発信スクリプト
# Usage: ruby transfer_test.rb [回数]

require "twilio-ruby"
require_relative "config"

count = (ARGV[0] || 1).to_i

client = Twilio::REST::Client.new(Config::TWILIO_ACCOUNT_SID, Config::TWILIO_AUTH_TOKEN)

count.times do |i|
  puts "[#{i + 1}/#{count}] 転送テスト発信中: #{Config::TWILIO_FROM_NUMBER} → #{Config::TEST_TO_NUMBER}"

  begin
    call = client.calls.create(
      to: Config::TEST_TO_NUMBER,
      from: Config::TWILIO_FROM_NUMBER,
      url: "#{Config::NGROK_URL}/twilio/voice?mode=transfer_test",
      status_callback: "#{Config::NGROK_URL}/twilio/status",
      status_callback_event: ["initiated", "ringing", "answered", "completed"]
    )
    puts "  CallSid: #{call.sid}"
  rescue => e
    puts "  エラー: #{e.message}"
  end

  # 連続テスト時は前のConferenceが終了するまで待つ
  sleep(60) if i < count - 1
end

puts "完了"
