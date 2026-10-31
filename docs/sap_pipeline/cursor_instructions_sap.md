# Okurite：SAP営業の週次自動化 Cursor指示書

## 0. 前提と守ること

- 対象は**日本国内・求人ボックスのみ**。海外とIndeedは今回は対象外。
- SAP営業先は**管理者の共有リスト**（`customers.client_id = NULL`）に登録する。送信は管理者の送信バッチ（`admin_id`、`form_submission_admin`キュー）で行う。優先度は変えない。
- **1社1行**。すでに登録がある会社は新しい行を作らず、業種に「SAP」を追記する。
- 下に書いた変更以外で、既存の動き（画面・送信・電話・課金）を変えない。
- 各Stepごとにコミットを分け、変更したファイルと確認手順を報告すること。
- マイグレーションは追加のみ。既存カラムの削除や型変更はしない。

---

## Step 1：業種の複数登録に対応する（完全一致 → 含む）

`customers.business` に「情報通信,SAP」のようにカンマ区切りで複数入れられるようにする。区切り文字は半角カンマに統一する（全角の「、」「，」は保存時に半角カンマに直す）。

1. `Customer` に次を追加する。
   - `business_list`：業種を配列で返す
   - `add_business!(name)`：まだ入っていなければ末尾に追記して保存する
   - scope `with_business(names)`：指定した業種のどれかを含む行を返す。部分一致の誤ヒット（例：「SAP」で「SAPPORO」）を避けるため、`',' || business || ','` に `',SAP,'` が含まれるかで判定する
2. 業種を完全一致で絞り込んでいる箇所を `with_business` に置き換える。
   - `app/controllers/form_submissions_controller.rb`：38〜40行目、338〜340行目
   - `app/controllers/customers_controller.rb`：136行目
   - `app/controllers/dashboard/dashboards_controller.rb`：146〜147行目
3. 業種の選択肢を作っている箇所は、カンマで分けた個々の業種を重複なしで並べるように直す。
   - `form_submissions_controller.rb`：86行目
   - `customers_controller.rb`：278〜283行目
   - `dashboards_controller.rb`：121行目、170〜171行目
4. `customers_controller.rb` の551行目（承認時の重複チェック）は変更しない。
5. 確認：業種「情報通信,SAP」の会社が、「SAP」で絞っても「情報通信」で絞っても表示されること。

---

## Step 2：差し込み欄（求人ごとに文面を変える）

1. マイグレーション：`customers.template_vars`（text、JSON文字列）を追加する。
2. `app/jobs/form_send_job.rb` の、本文を組み立てている箇所（`submission.content` を使っているところ）で、`{{キー}}` をその会社の `template_vars` の値に置き換える。
   - 使うキー：`job_title`（求人タイトル）、`company`（正式社名）、`area`（勤務地）
   - 値がないキーは、文面ごとに決めた代わりの文言に置き換える。代わりの文言がなければ空文字にする。
   - 置き換えたあとに `{{` か `}}` が残っていたら、**送信せず失敗として記録する**（status：「差し込みエラー」）。
3. 件名（`submission.title`）にも同じ置き換えをする。
4. 確認：テスト用の会社と文面で、置き換えた結果がログに出ること。値がない場合と、記号が残る場合の両方を試すこと。

---

## Step 3：求人ボックスの週次取得（box.py を Rails のジョブにする）

参照元は `docs/sap_pipeline/reference/box.py` と `box_url.csv`。本番でPythonに依存しないよう、**Ruby（Nokogiri）で書き直す**。

1. マイグレーション：`job_postings` テーブルを新しく作る。
   - カラム：`source`（'kyujinbox'）、`company_raw`、`company_clean`、`title`、`area`、`employ_type`、`posting_url`、`job_key`、`first_seen_at`、`last_seen_at`、`status`（new / resolved / skipped / registered）、`skip_reason`、`corporate_number`、`customer_id`
   - `job_key` には一意制約を付ける
2. `KyujinboxScrapeJob` を作る。
   - 起点URLは `config/sap_pipeline.yml` で管理する。初期値は次の2本（`docs/sap_pipeline/reference/box_url.csv` と同じ）。
     - `https://xn--pckua2a7gp15o89zb.com/SAP%E3%81%AE%E4%BB%95%E4%BA%8B?u=1`（SAPの仕事・本日の新着）
     - `https://xn--pckua2a7gp15o89zb.com/S4HANA%E3%81%AE%E4%BB%95%E4%BA%8B?u=1`（S4HANAの仕事・本日の新着）
   - `?u=1` は「本日の新着」（`?u=3` は3日以内。7日以内の指定はない）。**毎日1回巡回**して、その日の新着だけを取る。2026年10月28日時点で、SAPの本日の新着は約280件（12ページ程度）。
   - 取得する項目と、ページ送り（1ページごとに1秒待つ）は box.py と同じにする
   - 業種は「SAP」にする
   - 除外の条件は box.py と同じにする（社名が空、法人の種類が付いていない、「派遣」を含む）
   - 社名の重複判定は box.py と同じにする（法人の種類を除いた社名の先頭8文字）
3. **前の週に処理した会社を、もう一度処理しない。**
   - `job_key` は求人URLの `/jb/<ID>`、`/jbi/<ID>`、または `/rd/?uaid=<ID>` の値から作る（`uaid` は検索ページが違っても同じ求人なら同じ値になることを確認済み）。どれもなければ「社名＋タイトル」で作る。
   - `job_key` がすでにある求人は、`last_seen_at` を更新するだけで、後の処理に回さない。
   - 新しい求人でも、同じ `company_clean` を過去30日以内に処理済みなら、`status = skipped`（skip_reason：「30日以内に処理済み」）にして、後の処理に回さない。
   - 1ページ全部がすでに見た求人なら、そのURLの巡回を打ち切る。

---

## Step 4：正式社名と公式サイトの特定（gBizINFO）

`SapLeadResolveJob` を作る。`job_postings.status = new` の行だけを処理する。

1. **社名を整える**
   - 末尾の「〇〇オフィス」「〇〇支店」「〇〇営業所」「〇〇サテライト」「〇〇事業所」「〇〇支社」「〇〇センター」を取り除く
   - 途中で切れた社名（「...」で終わるもの）は、最後の語を取り除く
2. **法人番号を確定する**
   - gBizINFO REST API v2 で名前検索する。トークンは環境変数 `GBIZINFO_API_TOKEN` で渡す。コードには書かない。
   - 検索のパラメータ名と、存続している法人だけに絞る方法は、公式のAPIドキュメントで確認すること。
   - 閉鎖した法人は除き、全角・半角をそろえた社名が**完全一致する法人がちょうど1件**のときだけ確定とする。
   - 0件、または2件以上のときは `status = skipped` にする。skip_reason は「法人番号なし」または「同名複数」。登録はしない。
3. **公式サイトのURLを取る**
   - 確定した法人番号で、gBizINFOの基本情報から企業ホームページを取る。
   - URLが `BLOCKED_URL_PATTERNS` に当たる場合と、下の「追加の除外ドメイン」に当たる場合は、URLなしとして扱う。
   - URLが取れなかった会社は、既存のSERPでの補完（Bright Data）に回す。既存の `serp_status` の仕組みをそのまま使い、**URLが取れなかった会社だけ**を対象にする。
4. 結果を `job_postings` に保存する（`corporate_number`、`status = resolved`）。

### 追加の除外ドメイン（`config/initializers/blocked_urls.rb` にも追加する）

`xn--pckua2a7gp15o89zb.com`（求人ボックス）、`stanby.com`、`baseconnect.in`、`openwork.jp`、`en-hyouban.com`、`hrmos.co`、`airwork.net`、`herp.careers`、`jbplt.jp`、`job-medley.com`

---

## Step 5：登録前の重複チェックと登録

`SapLeadRegisterJob` を作る。`status = resolved` の行を処理する。

1. **登録の前に必ず既存の重複判定を実行する。** 業種は問わず、全件を対象にする。
   - 判定の材料は、既存の `Customer.normalized_name` と `Customer.name_similarity?`、電話番号の一致、`url` のドメインの一致。
2. **すでに登録がある場合**
   - `add_business!('SAP')` で業種を追記する
   - `template_vars` を今回の求人の内容で更新する
   - `url` が空なら、今回取れたURLを入れる
3. **登録がない場合**
   - 正式社名（gBizINFOの名称）、本店所在地、URL、業種「SAP」、`template_vars`、`client_id = NULL` で新しく作る
4. `job_postings` に `customer_id` を保存し、`status = registered` にする。
5. 既存のCSV取り込み処理（`CustomerImportService`）は使わない。社名の完全一致で上書きしてしまうため。

---

## Step 6：日曜のフォーム検出、月曜の送信

1. **日曜：** 業種にSAPを含み、`contact_url` が空で、`url` がある会社を対象に、既存の `ContactUrlDetectJob` を実行する。
2. **月曜：** `SapWeeklySendJob` を作る。
   - 対象は次をすべて満たす会社：
     - 業種にSAPを含む
     - `contact_url` がある
     - 既存の除外条件（`visible_on_form_send_list`、CAPTCHA NG、`deliverable_for`、`fobbiden`）に当たらない
     - **フォームへの送信成功（calls：call_type = 'form'、status = '自動送信成功'）が直近30日にない**
   - `admin_id` には `config/sap_pipeline.yml` の管理者ID、`submission_id` には同じファイルのSAP用の文面IDを入れて、`FormSubmissionBatch` を作る。キューへの投入は、画面から送るときと同じ経路（`PlanPriorityQueue`）で行う。
3. **ページ上の営業禁止文言を無視する設定**
   - `form_submission_batches.ignore_forbidden_text`（boolean、初期値 false）を追加する。
   - `SapWeeklySendJob` で作るバッチだけ true にする。
   - `FormSender` は、このフラグが true のときだけ、**ページ上の営業禁止文言による停止**を行わない。
   - `fobbiden` フラグ、配信停止（`delivery_opt_outs`）、URLの除外一覧は、これまで通り必ず守る。

---

## Step 7：定時実行の登録（`config/initializers/sidekiq_cron.rb`）

| 日時（JST） | ジョブ |
|---|---|
| 毎日 02:47 | `KyujinboxScrapeJob`（本日の新着を `job_postings` に貯めるだけ） |
| 土 03:17 | `SapLeadResolveJob` → `SapLeadRegisterJob`（その週に貯まった new の行をまとめて処理） |
| 日 03:17 | SERP補完（URLが取れなかった会社だけ）→ `ContactUrlDetectJob`（SAPで問い合わせURLが空の会社） |
| 月 09:13 | `SapWeeklySendJob` |
| 金 21:43 | `SapWeeklyReportJob`（Step 8） |

サーバーのタイムゾーンがJSTでない場合は、cronの時刻を変換すること。

---

## Step 8：週次レポートをGoogleスプレッドシートに書き込む

外部向けのAPIは作らない。集計結果を、既存のGoogleスプレッドシートに毎週1行追加する。

### 書き込み先

- スプレッドシートID：`1AcWed9iwArzUUt1lzymT7bpAh1en3X1TlmXQLLtI31Q`（名前：「Okurite SAP週次レポート」）
- 書き込むのは**最初のシート**。シート名は現在「Untitled」だが、名前で指定せず、先頭のシートを取得して使うこと。
- 1行目は見出しで、すでに入っている。2行目以降に追記する（values.append）。

### 認証

- Google Sheets API を、サービスアカウントで呼ぶ。
- 鍵ファイルのパスは、新しい環境変数 `SAP_REPORT_SHEETS_CREDENTIALS` で渡す。既存の `GOOGLE_APPLICATION_CREDENTIALS`（音声認識で使用中）は変更しない。
- gem は `google-apis-sheets_v4` と `googleauth` を使う。スコープは `https://www.googleapis.com/auth/spreadsheets`。

### 列と、集計に使うデータ（対象期間は前週土曜〜当週金曜）

| 列 | 見出し | 値 |
|---|---|---|
| A | 週開始日 | 対象期間の開始日（YYYY-MM-DD） |
| B | 週終了日 | 対象期間の終了日（YYYY-MM-DD） |
| C | 取得求人数 | 期間内に `last_seen_at` が更新された `job_postings` の件数 |
| D | 新規求人数 | 期間内に `first_seen_at` がある `job_postings` の件数 |
| E | 30日以内スキップ | skip_reason＝「30日以内に処理済み」の件数 |
| F | 法人番号なし | skip_reason＝「法人番号なし」の件数 |
| G | 同名複数 | skip_reason＝「同名複数」の件数 |
| H | 登録_新規 | Step 5 で新しく作った customers の件数 |
| I | 登録_業種追記 | Step 5 で既存の会社に業種SAPを追記した件数 |
| J | URL取得_gBizINFO | gBizINFOで公式サイトのURLが取れた件数 |
| K | URL取得_SERP | SERP補完でURLが取れた件数 |
| L | フォーム検出成功 | 日曜の検出で `contact_url` が入った件数 |
| M | フォーム未検出 | 日曜の検出で見つからなかった件数 |
| N | 送信数 | `SapWeeklySendJob` のバッチの処理件数 |
| O | 自動送信成功 | そのバッチの calls で status＝「自動送信成功」 |
| P | 自動送信失敗 | 同「自動送信失敗」 |
| Q | CAPTCHA NG | 同「CAPTCHA NG」 |
| R | 営業禁止 | 同「営業禁止」 |
| S | 差し込みエラー | 同「差し込みエラー」 |
| T | 配信停止 | 期間内に作られた `delivery_opt_outs` のうち、SAPの会社の件数 |
| U | クリック数 | 期間内の `click_logs` のうち、SAPバッチのリンクの件数 |
| V〜Y | 返信・問い合わせ数／商談数／受注数／メモ | **空欄のまま**（人が手で入力する） |

### 実行

- `SapWeeklyReportJob` を作り、Step 7 の表に **金 21:43（JST）** で追加する。
- 同じ週の行がすでにある場合（A列の日付が同じ）は、追記せず何もしない（二重書き込み防止）。
- 書き込みに失敗したら Rails のログに残し、管理画面の notifications にも1件作る。

---

## 完了報告に含めること

- 追加したマイグレーションの一覧
- 変更したファイルの一覧
- ローカルで各ジョブを1回ずつ手動で実行した結果
  - 求人ボックスは起点URL1本・2ページまでに制限して試すこと
  - 送信は自社のテスト用フォームだけに向けて試すこと
