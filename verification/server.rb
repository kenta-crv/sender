# frozen_string_literal: true

require "dotenv/load" rescue nil # .envファイルがあれば読み込み
require "sinatra"
require "twilio-ruby"
require "csv"
require "time"
require "uri"
require_relative "config"

set :port, Config::PORT
set :bind, "0.0.0.0"

# Rack::Protection::HostAuthorization を無効化（ngrok経由のアクセスを許可）
module Rack
  module Protection
    class HostAuthorization
      def accepts?(_env)
        true
      end
    end
  end
end

# --- Helpers ---

def write_csv(filename, headers, row)
  filepath = File.join(__dir__, "results", filename)
  is_new = !File.exist?(filepath)
  CSV.open(filepath, "a") do |csv|
    csv << headers if is_new
    csv << row
  end
end

def twiml_say(response, text)
  response.say(message: text, language: "ja-JP", voice: "Polly.Mizuki")
end

# 音声認識キーワード判定
def classify_speech(text)
  return ["unknown", nil] if text.nil? || text.empty?

  # 優先度: 転送（担当者に代わった） > 待ち > 断り > 不在 > 用件 > unknown
  # 「お待たせ」「担当」は転送完了を示すので、waitより先に判定
  case text
  when /待たせ|担当|代わり|かわりました|分かりました|繋ぐ|つなぎ|変わり/
    ["transfer", text]
  when /お待ち|待って|少々/
    ["wait", text]
  when /結構|必要ありません|間に合|いらない|大丈夫/
    ["rejection", text]
  when /不在|外出|席を外|いません|おりません|出かけ|留守/
    ["absent", text]
  when /用件/
    ["inquiry", text]
  else
    ["unknown", text]
  end
end

# --- Conference転送用のタイムスタンプ記録 ---
# call_sid => { transfer_initiated_at: Time, operator_joined_at: Time }
$transfer_timestamps = {}

# --- Endpoints ---

# テスト発信ページ
get "/" do
  content_type :html
  <<~HTML
    <!DOCTYPE html>
    <html lang="ja">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>Twilio自動発信テスト</title>
      <style>
        body { font-family: sans-serif; max-width: 600px; margin: 40px auto; padding: 0 20px; }
        h1 { font-size: 1.3em; }
        .info { background: #f0f0f0; padding: 15px; border-radius: 8px; margin: 20px 0; }
        .info p { margin: 5px 0; }
        .btn { display: inline-block; padding: 15px 30px; font-size: 1.1em; color: #fff; background: #2563eb; border: none; border-radius: 8px; cursor: pointer; text-decoration: none; }
        .btn:hover { background: #1d4ed8; }
        .btn:disabled { background: #9ca3af; cursor: not-allowed; }
        #result { margin-top: 20px; padding: 10px; display: none; border-radius: 8px; }
        .success { background: #d1fae5; color: #065f46; display: block !important; }
        .error { background: #fee2e2; color: #991b1b; display: block !important; }
        .steps { margin: 20px 0; }
        .steps li { margin: 8px 0; }
      </style>
    </head>
    <body>
      <h1>Twilio自動発信テスト</h1>
      <div class="info">
        <p><strong>発信先（相手役）:</strong> #{Config::TEST_TO_NUMBER}</p>
        <p><strong>オペレーター（転送先）:</strong> #{Config::OPERATOR_NUMBER}</p>
      </div>
      <ol class="steps">
        <li>下のボタンを押すと #{Config::TEST_TO_NUMBER} に電話がかかります</li>
        <li>電話に出ると、TTS挨拶が流れます</li>
        <li>「少々お待ちください」→ 間を置いて「お電話代わりました」と話してください</li>
        <li>音声認識で判定後、#{Config::OPERATOR_NUMBER} に自動転送されます</li>
        <li>#{Config::OPERATOR_NUMBER} が鳴ったら出てください → 通話接続</li>
      </ol>
      <button class="btn" id="callBtn" onclick="makeCall()">テスト発信する</button>
      <div id="result"></div>
      <script>
        function makeCall() {
          var btn = document.getElementById('callBtn');
          var result = document.getElementById('result');
          btn.disabled = true;
          btn.textContent = '発信中...';
          result.className = '';
          result.style.display = 'none';
          fetch('/test/call', { method: 'POST' })
            .then(function(r) { return r.json(); })
            .then(function(data) {
              if (data.status === 'ok') {
                result.textContent = '発信しました（CallSid: ' + data.call_sid + '）。電話に出てください。';
                result.className = 'success';
              } else {
                result.textContent = 'エラー: ' + data.error;
                result.className = 'error';
              }
              btn.disabled = false;
              btn.textContent = 'テスト発信する';
            })
            .catch(function(e) {
              result.textContent = '通信エラー: ' + e.message;
              result.className = 'error';
              btn.disabled = false;
              btn.textContent = 'テスト発信する';
            });
        }
      </script>
    </body>
    </html>
  HTML
end

# テスト発信API
post "/test/call" do
  content_type :json
  begin
    client = Twilio::REST::Client.new(Config::TWILIO_ACCOUNT_SID, Config::TWILIO_AUTH_TOKEN)
    call = client.calls.create(
      to: Config::TEST_TO_NUMBER,
      from: Config::TWILIO_FROM_NUMBER,
      url: "#{Config::NGROK_URL}/twilio/voice",
      status_callback: "#{Config::NGROK_URL}/twilio/status",
      status_callback_event: ["initiated", "ringing", "answered", "completed"]
    )
    { status: "ok", call_sid: call.sid }.to_json
  rescue => e
    { status: "error", error: e.message }.to_json
  end
end

# 通話接続時Webhook
post "/twilio/voice" do
  mode = params["mode"]

  response = Twilio::TwiML::VoiceResponse.new do |r|
    if mode == "transfer_test"
      # 転送テストモード: 挨拶後すぐにConference転送
      twiml_say(r, "転送テストを開始します。")
      r.redirect("/twilio/transfer?CallSid=#{params['CallSid']}", method: "POST")
    else
      # TTS挨拶を即再生 → 完了後にGatherで応答を待つ
      twiml_say(r, "お電話ありがとうございます。株式会社テストでございます。ご担当者様はいらっしゃいますでしょうか。")
      r.gather(
        input: "speech",
        language: "ja-JP",
        hints: "不在にしております,いません,おりません,いないです,留守にしております,出かけております,席を外しております,ご用件は,結構です,必要ありません,間に合っております,いらないです,大丈夫です,お電話代わりました,お電話かわりました,電話代わりました,少々お待ちください,お待ちください,お待たせしました,担当の",
        action: "/twilio/gather",
        method: "POST",
        timeout: 5,
        speech_timeout: 3
      )
      # Gatherタイムアウト時 → オペレーター転送
      r.redirect("/twilio/transfer?CallSid=#{params['CallSid']}", method: "POST")
    end
  end

  content_type "text/xml"
  response.to_s
end

# 音声認識結果受信
post "/twilio/gather" do
  speech_result = params["SpeechResult"]
  confidence = params["Confidence"]
  call_sid = params["CallSid"]

  category, matched_text = classify_speech(speech_result)

  puts "[GATHER] CallSid=#{call_sid} SpeechResult='#{speech_result}' Confidence=#{confidence} Category=#{category}"

  # CSV記録
  write_csv(
    "speech_recognition_log.csv",
    %w[timestamp call_sid speech_result confidence matched_category],
    [Time.now.iso8601, call_sid, speech_result, confidence, category]
  )

  response = Twilio::TwiML::VoiceResponse.new do |r|
    case category
    when "absent"
      twiml_say(r, "承知いたしました。不在とのことですね。改めてお電話させていただきます。失礼いたします。")
      r.hangup
    when "inquiry"
      twiml_say(r, "ありがとうございます。本日は新しいサービスのご案内でお電話いたしました。")
      r.hangup
    when "rejection"
      twiml_say(r, "承知いたしました。お時間いただきありがとうございました。失礼いたします。")
      r.hangup
    when "transfer"
      r.redirect("/twilio/transfer?CallSid=#{call_sid}", method: "POST")
    when "wait"
      # 相手が取り次ぎ中 → 再度Gatherで次の発話を待つ
      r.gather(
        input: "speech",
        language: "ja-JP",
        hints: "不在にしております,いません,おりません,いないです,留守にしております,出かけております,席を外しております,ご用件は,結構です,必要ありません,間に合っております,いらないです,大丈夫です,お電話代わりました,お電話かわりました,電話代わりました,少々お待ちください,お待ちください,お待たせしました,担当の",
        action: "/twilio/gather",
        method: "POST",
        timeout: 15,
        speech_timeout: 3
      )
      # タイムアウト時はオペレーター転送
      r.redirect("/twilio/transfer?CallSid=#{call_sid}", method: "POST")
    else
      twiml_say(r, "ありがとうございます。オペレーターにおつなぎいたします。")
      r.redirect("/twilio/transfer?CallSid=#{call_sid}", method: "POST")
    end
  end

  content_type "text/xml"
  response.to_s
end

# Conference転送
post "/twilio/transfer" do
  call_sid = params["CallSid"]
  conference_name = "transfer_#{call_sid}"

  # 転送開始時刻を記録
  $transfer_timestamps[call_sid] = { transfer_initiated_at: Time.now }

  puts "[TRANSFER] CallSid=#{call_sid} → Conference '#{conference_name}'"

  # REST APIでオペレーターをConferenceに呼び出し
  Thread.new do
    begin
      client = Twilio::REST::Client.new(Config::TWILIO_ACCOUNT_SID, Config::TWILIO_AUTH_TOKEN)
      operator_call = client.calls.create(
        to: Config::OPERATOR_NUMBER,
        from: Config::TWILIO_FROM_NUMBER,
        url: "#{Config::NGROK_URL}/twilio/operator_join?conference=#{conference_name}",
        status_callback: "#{Config::NGROK_URL}/twilio/status",
        status_callback_event: ["initiated", "ringing", "answered", "completed"]
      )
      puts "[TRANSFER] オペレーター発信成功: #{operator_call.sid}"
    rescue => e
      puts "[ERROR] オペレーター発信エラー: #{e.message}"
    end
  end

  # 発信者をConferenceに参加させる
  response = Twilio::TwiML::VoiceResponse.new do |r|
    r.dial do |d|
      d.conference(
        conference_name,
        start_conference_on_enter: true,
        end_conference_on_exit: true,
        status_callback: "#{Config::NGROK_URL}/twilio/conference/status",
        status_callback_event: "join leave"
      )
    end
  end

  content_type "text/xml"
  response.to_s
end

# オペレーター用: Conferenceに参加
post "/twilio/operator_join" do
  conference_name = params["conference"]

  puts "[OPERATOR_JOIN] Conference='#{conference_name}'"

  response = Twilio::TwiML::VoiceResponse.new do |r|
    twiml_say(r, "お客様との通話に接続します。")
    r.dial do |d|
      d.conference(
        conference_name,
        start_conference_on_enter: true,
        end_conference_on_exit: false,
        status_callback: "#{Config::NGROK_URL}/twilio/conference/status",
        status_callback_event: "join leave"
      )
    end
  end

  content_type "text/xml"
  response.to_s
end

# ステータス変更ログ
post "/twilio/status" do
  call_sid = params["CallSid"]
  status = params["CallStatus"]
  duration = params["CallDuration"]

  puts "[STATUS] CallSid=#{call_sid} Status=#{status} Duration=#{duration}"

  write_csv(
    "call_status_log.csv",
    %w[timestamp call_sid status duration],
    [Time.now.iso8601, call_sid, status, duration]
  )

  status 200
  ""
end

# Conference参加者イベント → 転送遅延計測
post "/twilio/conference/status" do
  conference_sid = params["ConferenceSid"]
  friendly_name = params["FriendlyName"] || ""
  event = params["StatusCallbackEvent"]
  call_sid = params["CallSid"]

  puts "[CONFERENCE] Event=#{event} ConferenceSid=#{conference_sid} FriendlyName=#{friendly_name} CallSid=#{call_sid}"

  # Conference名からオリジナルのCallSidを抽出
  original_call_sid = friendly_name.sub("transfer_", "") if friendly_name.start_with?("transfer_")

  if event == "participant-join" && original_call_sid
    ts = $transfer_timestamps[original_call_sid]
    if ts && ts[:transfer_initiated_at] && !ts[:operator_joined_at]
      # 2人目の参加者 = オペレーター参加
      # (1人目は発信者)
      ts[:operator_joined_at] = Time.now
      latency = (ts[:operator_joined_at] - ts[:transfer_initiated_at]).round(2)

      puts "[LATENCY] CallSid=#{original_call_sid} Latency=#{latency}s"

      write_csv(
        "transfer_latency_log.csv",
        %w[timestamp call_sid conference_sid transfer_initiated_at operator_joined_at latency_seconds],
        [
          Time.now.iso8601,
          original_call_sid,
          conference_sid,
          ts[:transfer_initiated_at].iso8601,
          ts[:operator_joined_at].iso8601,
          latency
        ]
      )
    end
  end

  status 200
  ""
end
