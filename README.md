# README

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