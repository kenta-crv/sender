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

### 起動

#### 推奨：一括起動スクリプト

senderディレクトリで、お使いのOSに合わせて以下を実行してください。
4つのサービスが自動的に別ウィンドウで起動します。

**macOS:**
```
chmod +x start_dev.sh   # 初回のみ
./start_dev.sh
```

**Windows:**
```
start_dev.bat をダブルクリック
```

#### 手動起動（スクリプトが動かない場合）

ターミナルを4つ開き、それぞれで以下を実行：

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

#### メインプロセス（全キュー）
```
bundle exec sidekiq -C config/sidekiq.yml
```

#### SERP補完専用プロセス（並列数3に制限・フォーム送信と競合しない）
```
bundle exec sidekiq -C config/sidekiq_enrichment.yml
# または個別指定:
bundle exec sidekiq -q serp_enrichment -c 3
```

キュー構成:
- `form_submission` (priority 5) … フォーム送信ワーカー（既存）
- `auto_dial` (priority 4) … 自動架電ワーカー（既存）
- `article_generation` (priority 3) … 記事生成ワーカー（既存）
- `serp_enrichment` (priority 1) … SERP補完専用（SerpPipelineDbWorker）

非同期実行:
```ruby
SerpPipelineDbWorker.perform_async('軽貨物', 200)  # DB mode 非同期実行
```

SerpPipelineWorker.perform_async('path/to/list.csv')  # CSV mode（旧）

### 企業ディレクトリサイトのブラックリスト管理
SERPで取得したURLが企業ディレクトリサイトの場合、`url` フィールドへの保存を自動的にスキップします。
ブラックリストへのドメイン追加方法・現在の登録済みドメイン一覧は以下を参照してください:

→ [docs/blacklist.md](docs/blacklist.md)

### 抽出率確認
ExtractTracking.last(5).each { |t| puts "#{t.industry}: #{t.success_count}/#{t.total_count}" }

### ステータス確認（SERP補完の進捗）
Customer.group(:status).count
# serp_queued: 実行中, serp_done: 完了, nil: 未実行

#Sidekiq apply
git pull
bash bin/setup_sidekiq.sh

#ログ削除
bash bin/cleanup_logs.sh