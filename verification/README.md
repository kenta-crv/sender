# Twilio自動発信 検証環境

音声認識 → 判定 → オペレーター転送の一連フローを検証するためのテスト環境です。

## セットアップ

### 1. 依存gemのインストール

```bash
cd verification
bundle install
```

### 2. 環境変数の設定

`.env.sample` をコピーして `.env` を作成し、値を設定してください。

```bash
cp .env.sample .env
```

```
TWILIO_ACCOUNT_SID=ACxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_AUTH_TOKEN=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
TWILIO_FROM_NUMBER=+12543263758
TEST_TO_NUMBER=+81XXXXXXXXXX      # 発信先番号（E.164形式）
OPERATOR_NUMBER=+81XXXXXXXXXX     # オペレーター転送先番号（E.164形式）
NGROK_URL=https://xxxxx.ngrok-free.dev  # 手順3で取得したURL
```

**電話番号のE.164形式について:**
- 090-1234-5678 → `+819012345678`
- 080-1234-5678 → `+818012345678`
- 03-1234-5678 → `+81312345678`

### 3. ngrokの起動

```bash
ngrok http 4567
```

表示された `Forwarding` のURLを `.env` の `NGROK_URL` に設定してください。

### 4. サーバーの起動

```bash
ruby server.rb
```

### 5. テスト実行

ブラウザで ngrokのURL にアクセスすると、テスト発信ページが表示されます。
「テスト発信する」ボタンを押すと、`TEST_TO_NUMBER` に電話がかかります。

## テストの流れ

1. ボタンを押す → `TEST_TO_NUMBER` に着信 → 出る
2. TTS挨拶「ご担当者様はいらっしゃいますでしょうか」が流れる
3. 以下のいずれかを話す：
   - 「少々お待ちください」→ 待機（再度音声認識）
   - 「お電話代わりました」→ オペレーター転送
   - 「不在にしております」→ 不在応答 → 切断
   - 「結構です」→ お断り応答 → 切断
4. 転送の場合 → `OPERATOR_NUMBER` が鳴る → 出る → 通話接続

## テスト結果の確認

`results/` フォルダにCSVで記録されます：

- `speech_recognition_log.csv` — 音声認識結果（発話内容・判定カテゴリ・信頼度）
- `transfer_latency_log.csv` — 転送遅延（転送開始〜オペレーター参加の秒数）
- `call_status_log.csv` — 通話ステータス変更ログ

## 音声認識キーワードのチューニング

`server.rb` の `classify_speech` メソッドでキーワードを管理しています。

```ruby
def classify_speech(text)
  case text
  when /待たせ|担当|代わり|かわりました|分かりました/
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
```

**キーワード追加方法:**
各カテゴリの正規表現に `|新しいキーワード` を追加してください。
例: 「間に合ってます」を断りに追加 → `/結構|必要ありません|間に合|いらない|大丈夫|間に合ってます/`

**認識精度の改善:**
`/twilio/voice` エンドポイント内の `hints` パラメータに認識候補を追加すると、
Twilioの音声認識エンジンがそのフレーズを優先的に認識するようになります。

## 注意事項

- テスト発信にはTwilio通話料が発生します（トライアルクレジットから差し引き）
- `TEST_TO_NUMBER` と `OPERATOR_NUMBER` は別の端末にしてください（同時に受ける必要があるため）
- ngrokを再起動するとURLが変わるため、`.env` の `NGROK_URL` も更新してください
