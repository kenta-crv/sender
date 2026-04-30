# 業種（industry）の抽出ロジック

本ドキュメントは取引先向けに、`Customer.industry` / `Customer.business` /
`Customer.genre` の各カラムが SERP 補完パイプラインでどのように扱われているかを
説明するものです。

## 結論

SERP 補完パイプラインで **業種を能動的に抽出するロジックは現状ありません**。
SERP API のレスポンスに業種ラベルが含まれている特定のケースでのみ
`industry` が埋まります。

## カラム別の挙動

| カラム      | パイプラインでセット | ソース |
|------------|---------------------|--------|
| `industry` | ◯（限定的）         | SERP `local_results.type` / `local_results.category` / `knowledge_graph.type` |
| `business` | ✗                   | パイプライン外（手動入力 / 別フロー） |
| `genre`    | ✗                   | パイプライン外（手動入力 / 別フロー） |

## industry が埋まる条件

`app/services/bright_data/company_extractor.rb` を参照:

```ruby
# 1. organic_results（通常の Web 検索結果）
#    → industry: nil  （常に未設定）

# 2. local_results（Google Maps 系のローカルカード）
#    → industry: item["type"] || item["category"]
#    例: "Web designer" / "IT services"

# 3. knowledge_graph（ナレッジパネル）
#    → industry: kg["type"]
#    例: "Software company"
```

つまり、SERP 検索結果に **Google Maps カード or ナレッジパネルが付随した場合のみ**
業種ラベルが取れます。一般的な B2B 検索（例: "〇〇株式会社 会社概要"）では
これらが付かないクエリが多く、`industry` が埋まる確率は低いのが正常動作です。

## TARGET_INDUSTRIES によるフィルタ

`CompanyExtractor.filter_by_industry` で、業種が取得できた場合のみ
`TARGET_INDUSTRIES` 定数（IT / Web / システム / コンサルティング 等）に
含まれるかどうかでフィルタリングしています。
**業種が nil（未取得）のレコードは無条件で通します**。

## WebEnricher（HTMLクロール）の対応

`app/services/bright_data/web_enricher.rb` では業種抽出は実装していません。
WebEnricher が補完するのは tel / address / contact_url / company（会社名）の
4 項目のみです。

## 業種抽出を強化したい場合

業種を網羅的に埋めたい場合は別ロジックの実装が必要です。候補:

1. クロール HTML の `<meta name="keywords">` から業種ワードを推定
2. 既存の `Crowdwork.title`（業種マスター）と社名・URL から推測
3. 外部 API（法人番号 API、LinkedIn 等）連携
4. LLM による分類（取引先方針で Gemini は使わない方針のため OpenAI 等を別途）

いずれも本パイプラインの責任範囲外であるため、別 issue で要件定義の上、
専用サービス（例: `BrightData::IndustryClassifier`）として実装するのが
望ましいと判断しています。
