# README

## Twilio自動発信 セットアップ手順

### 必要なサービス（すべて起動が必要）

自動発信機能は以下の4プロセスが**すべて起動している状態**で動作します。
どれか1つでも欠けると発信されません。

| # | サービス | 役割 | 起動コマンド |
|---|---------|------|-------------|
| 1 | Redis | ジョブキュー | `redis-server` |
| 2 | Sidekiq | バックグラウンドジョブ実行（**発信処理本体**） | `bundle exec sidekiq` |
| 3 | Rails | Webサーバー・UI | `bundle exec rails server` |
| 4 | ngrok | Twilio Webhook受信用の公開URL | `ngrok http 3000` |

### セットアップ

1. コード取得・依存関係インストール
   ```
   git pull origin feature/verification-test
   bundle install
   rails db:migrate
   ```

2. Google Cloud Speech APIのキー（JSON）を配置し、`.env` に設定
   ```
   GOOGLE_APPLICATION_CREDENTIALS=/path/to/your-service-account.json
   ```

3. `.env` の `NGROK_URL` をngrokで表示されたURLに更新

4. ストリームモード有効化（初回のみ）
   ```
   rails console
   > TwilioConfig.current.update(stream_mode_enabled: true)
   ```

### 起動（ターミナル4つ）

```
# ターミナル1: Redis
redis-server

# ターミナル2: Sidekiq（これを忘れると発信されません）
cd sender && bundle exec sidekiq

# ターミナル3: ngrok
ngrok http 3000

# ターミナル4: Rails
cd sender && bundle exec rails server
```

### 発信テスト

- `/call_batches/dashboard` → 「新規発信」から発信
- バッチを作成しても発信が始まらない場合は、**Sidekiqのログ**を確認してください

### トラブルシューティング

| 症状 | 原因 | 対処 |
|------|------|------|
| バッチは作られるが発信されない | Sidekiq未起動 | `bundle exec sidekiq` を実行 |
| Sidekiq起動時にRedis接続エラー | Redis未起動 | `redis-server` を実行 |
| Twilio Webhookが届かない | ngrok URL未更新 | `.env` の `NGROK_URL` を更新してRails再起動 |
| Google Speech認証エラー | JSONキーパス誤り | `.env` の `GOOGLE_APPLICATION_CREDENTIALS` を絶対パスで指定 |

---

This README would normally document whatever steps are necessary to get the
application up and running.

Things you may want to cover:

* Ruby version

* System dependencies

* Configuration

* Database creation

* Database initialization

* How to run the test suite

* Services (job queues, cache servers, search engines, etc.)

* Deployment instructions

* ...

## SERP API リスト収集

### 環境変数
BRIGHT_DATA_API_KEY=xxx
BRIGHT_DATA_ZONE=xxx

### パイプライン実行
# dry_run
bundle exec rails runner "BrightData::Pipeline.execute(csv_path: 'path/to/list.csv', dry_run: true)"

# 本番
bundle exec rails runner "BrightData::Pipeline.execute(csv_path: 'path/to/list.csv', detect_contact: true)"

### DB内の不完全データを対象にSERP補完（UIから起動可能）
# 実行対象条件（いずれかに該当するレコード）:
#   - company に法人格（株式会社等）を含まない
#   - tel が空
#   - address に都道府県が含まれない
#   - url が空
# 実行済みレコードは status = "serp_queued" → "serp_done" で管理（ループ防止）

# コマンドラインから実行
bundle exec rails runner "BrightData::Pipeline.execute_from_db(industry: '軽貨物', limit: 100)"

# UIから実行: /customers/draft → 「SERP補完開始」ボタン
# （業種フィルタ・件数上限をフォームで指定可能）

### Sidekiq（大量データ時）
bundle exec sidekiq -q serp
SerpPipelineWorker.perform_async('path/to/list.csv')
SerpPipelineDbWorker.perform_async('軽貨物', 200)  # DB modeの非同期実行

### 抽出率確認
ExtractTracking.last(5).each { |t| puts "#{t.industry}: #{t.success_count}/#{t.total_count}" }

### ステータス確認（SERP補完の進捗）
Customer.group(:status).count
# serp_queued: 実行中, serp_done: 完了, nil: 未実行
