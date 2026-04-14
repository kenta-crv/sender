# 企業ディレクトリサイト ブラックリスト管理

## 概要

SERP検索結果に企業ディレクトリサイト（求人サイト・法人情報DB・地図サービス等）の
URLが含まれることがあります。これらは対象企業の「自社サイト」ではないため、
`url` フィールドへの保存対象から除外する仕組みがあります。

ブラックリストに登録されたドメインは **url フィールドには保存されません**。
ただし tel / address / contact_url の抽出には引き続き使用されます。

---

## ブラックリストの定義場所

**ファイル:** `app/services/bright_data/web_enricher.rb`

```ruby
DIRECTORY_DOMAINS = %w[
  cnavi.g-search.or.jp
  en-hyouban.com
  baseconnect.in
  ...
].freeze
```

クラス定数 `BrightData::WebEnricher::DIRECTORY_DOMAINS` として定義されています。

---

## 現在のブラックリスト（26ドメイン）

| ドメイン | 種別 |
|---------|------|
| cnavi.g-search.or.jp | 企業情報DB（帝国データバンク系） |
| en-hyouban.com | 企業口コミ・評判サイト |
| baseconnect.in | 法人情報検索 |
| houjin.jp | 法人情報検索 |
| houjin-bangou.nta.go.jp | 国税庁法人番号公表サイト |
| alarmbox.jp | 企業口コミ・評判サイト |
| mapion.co.jp | 地図サービス |
| navitime.co.jp | 地図・ナビサービス |
| itp.ne.jp | 電話帳・タウンページ |
| ekiten.jp | 店舗・企業情報サイト |
| tdb.co.jp | 帝国データバンク |
| dun.co.jp | ダン＆ブラッドストリート（企業情報） |
| nikkei.com | 日本経済新聞（企業情報） |
| job-medley.com | 求人サイト |
| openwork.jp | 企業口コミ・求人サイト |
| vorkers.com | 企業口コミサイト |
| bunshun.jp | 文春オンライン |
| diamond.jp | ダイヤモンドオンライン |
| r.gnavi.co.jp | ぐるなび（飲食店情報） |
| tabelog.com | 食べログ（飲食店情報） |
| hotpepper.jp | ホットペッパー（飲食・美容） |
| homes.co.jp | LIFULL HOME'S（不動産） |
| suumo.jp | SUUMO（不動産） |
| minkabu.jp | みんかぶ（株式・金融情報） |
| yahoo.co.jp | Yahoo! Japan（各種情報） |
| yelp.co.jp | Yelp（口コミサイト） |

---

## ドメインを追加する手順

### 1. ファイルを開く

```
app/services/bright_data/web_enricher.rb
```

### 2. `DIRECTORY_DOMAINS` 定数にドメインを追記する

```ruby
DIRECTORY_DOMAINS = %w[
  cnavi.g-search.or.jp
  en-hyouban.com
  # ... 既存のドメイン ...
  新しいドメイン.co.jp   # ← ここに追加（1行1ドメイン、コメント可）
].freeze
```

**記法のルール:**
- 1行1ドメイン
- `www.` なしのベースドメインで記載（`www.` は自動的に除去されます）
- `#` でコメントを付けることができます
- サブドメインも自動的にマッチします（例: `map.yahoo.co.jp` は `yahoo.co.jp` で捕捉）

### 3. 動作確認

追加後、以下のコマンドで正しく判定されるか確認します：

```ruby
# rails console で確認
BrightData::WebEnricher.directory_url?('https://追加したドメイン.co.jp/some/path')
# => true が返れば正常
```

または実際の SERP 補完ログで確認：

```
# ログに以下が出力される場合、ブラックリスト判定が動作している
# (url フィールドへの保存がスキップされ、他フィールドは抽出対象のまま)
```

### 4. 確認用クエリ

補完後に url フィールドがブラックリストドメインで埋まっていないか確認：

```ruby
# rails runner
domains_to_check = %w[cnavi.g-search.or.jp baseconnect.in]
domains_to_check.each do |domain|
  count = Customer.where("url LIKE ?", "%#{domain}%").count
  puts "#{domain}: #{count}件" if count > 0
end
```

---

## よくあるパターン（追加が必要になりやすいドメイン）

- 求人サイト: `indeed.com`, `doda.jp`, `rikunabi.com`, `mynavi.jp`
- 不動産情報: `athome.co.jp`, `chintai.net`
- 地図・ナビ: `google.com/maps`, `map.yahoo.co.jp`
- 法人情報: `ubie.app`, `biz.nifty.com`
- SNS・メディア: `facebook.com`, `twitter.com`, `instagram.com`
