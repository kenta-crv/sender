require "test_helper"

class CompanyInfoExtractorTest < ActiveSupport::TestCase
  test "clean_address removes google map label after address" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "福岡県行橋市東大橋4丁目1570-1",
      extractor.send(:clean_address, "福岡県行橋市東大橋4丁目1570-1 Google map")
    )
  end

  test "extract prefers address and tel near branch name" do
    customer = Customer.new(company: "株式会社シーエル 宇美東センター")
    extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <body>
          <p>株式会社シーエル本社 〒812-0863 福岡県福岡市博多区金の隈3丁目14番3号CL会館 TEL:092-504-1708</p>
          <p>宇美東センター 〒811-2125 福岡県糟屋郡宇美町宇美東3丁目8番24号 TEL:092-410-7788</p>
        </body>
      </html>
    HTML

    assert_equal "092-410-7788", extractor.extract[:tel]
    assert_equal "福岡県糟屋郡宇美町宇美東3丁目8番24号", extractor.extract[:address]
  end

  test "extract uses customer locality when branch label differs on listing page" do
    customer = Customer.new(
      company: "株式会社シーエル 筑紫野三井センター",
      address: "福岡県 筑紫野市 桜台駅 徒歩8分"
    )
    extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <body>
          <p>配送センター 〒816-0062 福岡市博多区立花寺1-7-1 TEL:092-504-7515</p>
          <p>筑紫野センター 〒818-0065 福岡県筑紫野市大字諸田174-2 TEL:092-919-7830FAX:092-919-7831</p>
        </body>
      </html>
    HTML

    assert_equal "092-919-7830", extractor.extract[:tel]
    assert_equal "福岡県筑紫野市大字諸田174-2", extractor.extract[:address]
  end

  test "extract uses place prefix from branch-like company name" do
    customer = Customer.new(company: "川口配送センター／イオンネクストデリバリー株式会社")
    extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <body>
          <p>本社 〒261-0023 千葉県千葉市美浜区中瀬1丁目6</p>
          <p>川口営業所 〒334-0056 埼玉県川口市大字峯91-1</p>
        </body>
      </html>
    HTML

    assert_equal "埼玉県川口市大字峯91-1", extractor.extract[:address]
  end

  test "extract_tel ignores uuid fragments" do
    extractor = CompanyInfoExtractor.new(<<~HTML)
      <html>
        <body>
          <script>window.appId = "141995eb-c700-8487-6366-a482f7432e2b";</script>
          <meta property="og:image" content="https://example.com/assets/aa7f6a83-a072-4448-9300-eac35d22ae2b">
          <p>電話番号は掲載していません</p>
        </body>
      </html>
    HTML

    assert_nil extractor.extract[:tel]
  end

  test "extract_tel normalizes unusual hyphen characters" do
    extractor = CompanyInfoExtractor.new(<<~HTML)
      <html>
        <body>
          <p>電話番号03₋5817₋8441</p>
          <p>秋田営業所0184-38-2561</p>
        </body>
      </html>
    HTML

    assert_equal "03-5817-8441", extractor.extract[:tel]
  end

  test "extract_tel normalizes parenthesized area code and plain tel links" do
    extractor = CompanyInfoExtractor.new(<<~HTML)
      <html>
        <body>
          <p>TEL:(093)671-0344</p>
        </body>
      </html>
    HTML

    assert_equal "093-671-0344", extractor.extract[:tel]

    link_only = CompanyInfoExtractor.new(<<~HTML)
      <html><body><a href="tel:09036742727">電話</a></body></html>
    HTML

    assert_equal "090-3674-2727", link_only.extract[:tel]
  end

  test "extract_tel keeps toll free 0800 prefix intact" do
    extractor = CompanyInfoExtractor.new(<<~HTML)
      <html>
        <body>
          <p>TEL: 0800-919-9966</p>
        </body>
      </html>
    HTML

    assert_equal "0800-919-9966", extractor.extract[:tel]

    link_only = CompanyInfoExtractor.new(<<~HTML)
      <html><body><a href="tel:08009199966">TEL</a></body></html>
    HTML

    assert_equal "0800-919-9966", link_only.extract[:tel]
  end

  test "extract_tel rejects studio uuid fragments that look like phone numbers" do
    extractor = CompanyInfoExtractor.new(<<~HTML)
      <html>
        <body>
          <script>window.__NUXT__ = {"uuid":"b609716b-7cbb-40e3-a835-f56fb72892f5","style":"0922-4216-835"};</script>
        </body>
      </html>
    HTML

    assert_nil extractor.extract[:tel]
  end

  test "extract_tel prefers company table label over later tel links" do
    extractor = CompanyInfoExtractor.new(<<~HTML)
      <html>
        <body>
          <table>
            <tr><th>電話番号</th><td>03₋5817₋8441</td></tr>
          </table>
          <a href="tel:0184-38-2561">秋田営業所</a>
        </body>
      </html>
    HTML

    assert_equal "03-5817-8441", extractor.extract[:tel]
  end

  test "extract_contact_url uses contact link text" do
    extractor = CompanyInfoExtractor.new(<<~HTML)
      <html>
        <body>
          <a href="/SITEINFO/index.html">お問い合わせ</a>
        </body>
      </html>
    HTML

    assert_equal "/SITEINFO/index.html", extractor.extract[:contact_url]
  end

  test "extract_contact_url ignores tracking inquiry links" do
    extractor = CompanyInfoExtractor.new(<<~HTML)
      <html>
        <body>
          <a href="/webtrace/">お問い合わせ番号照会</a>
          <a href="/contact/">お問い合わせ</a>
        </body>
      </html>
    HTML

    assert_equal "/contact/", extractor.extract[:contact_url]
  end

  test "extract_company keeps full corporate name from title" do
    extractor = CompanyInfoExtractor.new(<<~HTML)
      <html>
        <head>
          <title>株式会社島田建材 ｜ 埋立、造成、一般建設、土木工事</title>
        </head>
        <body></body>
      </html>
    HTML

    assert_equal "株式会社島田建材", extractor.extract[:company]
  end

  test "extract_company prefers labeled profile company" do
    extractor = CompanyInfoExtractor.new(<<~HTML)
      <html>
        <head><title>会社概要 ｜ 株式会社サンプル物流</title></head>
        <body>
          <table>
            <tr><th>社名</th><td>株式会社サンプル物流</td></tr>
          </table>
        </body>
      </html>
    HTML

    assert_equal "株式会社サンプル物流", extractor.extract[:company]
  end

  test "extract_address infers omitted prefecture from customer address" do
    customer = Customer.new(company: "株式会社シーエル", address: "福岡県 福岡市 雑餉隈駅 車10分")
    extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <body>
          <table>
            <tr><th>所在地</th><td>〒812-0863　福岡市博多区金の隈3丁目14番3号【本社CL会館】</td></tr>
            <tr><th>TEL</th><td>092-504-1708</td></tr>
          </table>
        </body>
      </html>
    HTML

    assert_equal "福岡県福岡市博多区金の隈3丁目14番3号", extractor.extract[:address]
  end

  test "extract_address reads labeled head office text outside tables" do
    customer = Customer.new(address: "福岡県 福岡市")
    extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <body>
          <p>本社 〒813-0034 福岡市東区多の津1丁目14番1号 FRCビル7階</p>
          <p>TEL 092-622-2376</p>
        </body>
      </html>
    HTML

    assert_equal "福岡県福岡市東区多の津1丁目14番1号 FRCビル7階", extractor.extract[:address]
  end

  test "clean_address removes trailing map link text" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "大阪府大阪市淀川区宮原1-1-1　新大阪阪急ビル3階",
      extractor.send(:clean_address, "大阪府大阪市淀川区宮原1-1-1　新大阪阪急ビル3階　（→MAPを見る）")
    )
  end

  test "clean_address removes copyright tail" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "東京都千代田区外神田6丁目7-7 マツダビル 4階",
      extractor.send(:clean_address, "東京都千代田区外神田6丁目7-7 マツダビル 4階 Copyright © 2025")
    )
  end

  test "clean_address removes following company navigation text" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "兵庫県神戸市中央区八幡通3丁目1番14号サンシポートビル6F",
      extractor.send(:clean_address, "兵庫県神戸市中央区八幡通3丁目1番14号サンシポートビル6F 事業案内 施工計画策定・管理 会社情報")
    )
  end

  test "clean_address removes phone number tail without tel label" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "広島県広島市安佐北区上深川町304-6",
      extractor.send(:clean_address, "広島県広島市安佐北区上深川町304-6 082-562-2624 TOP 会社概要")
    )
  end

  test "clean_address keeps first office before second postal address" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "大阪府東大阪市水走1-18-26",
      extractor.send(:clean_address, "大阪府東大阪市水走1-18-26 第二工場 〒578-0921 大阪府東大阪市水走3-8-4")
    )
  end

  test "clean_address keeps first office before second named office address" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "福岡県粕屋郡新宮町大字立花口2308-2",
      extractor.send(:clean_address, "福岡県粕屋郡新宮町大字立花口2308-2 八女営業所福岡県八女市稲富6-1")
    )
  end

  test "clean_address keeps head office before bracketed office postal address" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "神奈川県川崎市宮前区東有馬1-17-18",
      extractor.send(:clean_address, "神奈川県川崎市宮前区東有馬1-17-18 ［本社営業所］ 〒224-0043 神奈川県横浜市都筑区折本町1186番地")
    )
  end

  test "clean_address removes trailing angle bracket office label" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "神奈川県藤沢市辻堂新町2-12-27",
      extractor.send(:clean_address, "神奈川県藤沢市辻堂新町2-12-27 ＜営業所＞ ・")
    )
  end

  test "clean_address keeps first address when multiple prefectures are concatenated" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "神奈川県横浜市都筑区大棚町445-1",
      extractor.send(:clean_address, "神奈川県横浜市都筑区大棚町445-1神奈川県川崎市宮前区宮前平小台1-18-1")
    )
  end

  test "extract_address keeps first delivery base from concatenated office text" do
    customer = Customer.new(company: "志村運送株式会社", address: "神奈川県 横浜市 都筑区")
    extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <body>
          <p>当社は神奈川県を中心に軽貨物運送事業を展開しています。</p>
          <p>配達拠点 神奈川県横浜市都筑区大棚町445-1神奈川県川崎市宮前区宮前平小台1-18-1</p>
        </body>
      </html>
    HTML

    assert_equal "神奈川県横浜市都筑区大棚町445-1", extractor.extract[:address]
  end

  test "clean_address rejects history fragments after city level text" do
    extractor = CompanyInfoExtractor.new("")

    assert_nil(
      extractor.send(:clean_address, "千葉県市原市） 平成11年 8月 一般労働者派遣事業の認可を受ける")
    )
  end

  test "clean_address rejects city level marketing phrases" do
    extractor = CompanyInfoExtractor.new("")

    assert_nil extractor.send(:clean_address, "愛知県知立市の軽貨物運送会社")
    assert_nil extractor.send(:clean_address, "神奈川県下27の自治体・行政区に拡がっています。（2024年4月現在）")
  end

  test "clean_address rejects json ld description fragments" do
    extractor = CompanyInfoExtractor.new("")

    assert_nil extractor.send(
      :clean_address,
      "埼玉県富士見市の軽貨物運送業\",\"potentialAction\":[{\"@type\":\"SearchAction\",\"target\":{\"urlTemplate\":\"https://example.com/?s={search_term}\"}"
    )
  end

  test "clean_address removes trailing business category word" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "大阪府大阪市東成区玉津1丁目1-8",
      extractor.send(:clean_address, "大阪府大阪市東成区玉津1丁目1-8 建　築")
    )
  end

  test "clean_address removes trailing business description words" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "大阪府大阪市中央区宗右衛門町1-9",
      extractor.send(:clean_address, "大阪府大阪市中央区宗右衛門町1-9 有料職業紹介事業 WEB広告事業 デジタルサイネージ事業 ©")
    )
  end

  test "clean_address removes bracketed head office phone label" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "東京都杉並区天沼３－３０－４０フヨウハウス２０３号",
      extractor.send(:clean_address, "東京都杉並区天沼３－３０－４０フヨウハウス２０３号[本社代表")
    )
    assert_equal(
      "神奈川県川崎市川崎区駅前本町１１番地２　川崎フロンティアビル４F",
      extractor.send(:clean_address, "神奈川県川崎市川崎区駅前本町１１番地２　川崎フロンティアビル４F【代表")
    )
  end

  test "clean_address removes trailing decorative symbols" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "福岡県福津市上西郷2054-1",
      extractor.send(:clean_address, "福岡県福津市上西郷2054-1■")
    )
    assert_equal(
      "神奈川県高座郡寒川町一之宮5-10-6 湘南BASE R103",
      extractor.send(:clean_address, "神奈川県高座郡寒川町一之宮5-10-6 湘南BASE R103【")
    )
  end

  test "clean_address removes google map and inquiry labels" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "佐賀県伊万里市立花町30-17",
      extractor.send(:clean_address, "佐賀県伊万里市立花町30-17GoogleMapで見る")
    )
    assert_equal(
      "福岡県福岡市東区箱崎ふ頭2-2-41",
      extractor.send(:clean_address, "福岡県福岡市東区箱崎ふ頭2-2-41 Google MAPで確認")
    )
    assert_equal(
      "鹿児島県鹿児島市下荒田1丁目6-23 SGウイング荒田2F",
      extractor.send(:clean_address, "鹿児島県鹿児島市下荒田1丁目6-23 SGウイング荒田2F お問い合わせ")
    )
    assert_equal(
      "大阪府大阪市住之江区御崎6-3-1 吉川ロジスティクスグループビル内3階",
      extractor.send(:clean_address, "大阪府大阪市住之江区御崎6-3-1 吉川ロジスティクスグループビル内3階 MAP")
    )
  end

  test "clean_address removes trailing office label after street address" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "福岡県福岡市早良区田村3-23-6",
      extractor.send(:clean_address, "福岡県福岡市早良区田村3-23-6 長浜営業所")
    )
  end

  test "clean_address removes annotation tail" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "福岡県北九州市小倉北区西港町15-76",
      extractor.send(:clean_address, "福岡県北九州市小倉北区西港町15-76 ※本社所在地は戸畑港運輸株式會社となります")
    )
  end

  test "clean_address rejects work condition text mistaken as address" do
    extractor = CompanyInfoExtractor.new("")

    assert_nil extractor.send(
      :clean_address,
      "神奈川県相模原市南区若松 荷物積み込み場 神奈川県相模原市南区若松 時間 8時から20時"
    )
  end

  test "clean_address removes officer and email tails" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "大阪府大阪市中央区城見1-2-27　クリスタルタワー 3F",
      extractor.send(:clean_address, "大阪府大阪市中央区城見1-2-27　クリスタルタワー 3F 役員 代表取締役会長寺田 寿男")
    )
    assert_equal(
      "神奈川県横浜市神奈川区鶴屋町2丁目22番3号伊藤ビル4階",
      extractor.send(:clean_address, "神奈川県横浜市神奈川区鶴屋町2丁目22番3号伊藤ビル4階 info@yegren.co.jp")
    )
    assert_equal(
      "神奈川県横浜市鶴見区栄町通１丁目５−１２",
      extractor.send(:clean_address, "神奈川県横浜市鶴見区栄町通１丁目５−１２chinen.alliance_at_bh.wakwak.com")
    )
  end

  test "clean_address removes embedded second office postal address" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "神奈川県横浜市港北区新羽町673-1",
      extractor.send(:clean_address, "神奈川県横浜市港北区新羽町673-1法人営業部〒223-0057神奈川県横浜市港北区新羽町673-1")
    )
    assert_equal(
      "福岡県大野城市御笠川5丁目9-9",
      extractor.send(:clean_address, "福岡県大野城市御笠川5丁目9-9博多営業所〒812-0892福岡県福岡市博多区東那珂２丁目10-55")
    )
    assert_equal(
      "熊本県熊本市中央区島崎1丁目1-19",
      extractor.send(:clean_address, "熊本県熊本市中央区島崎1丁目1-19本店〒870-0917大分市高松1丁目7番36号　サンシャイン高城 1F")
    )
    assert_equal(
      "神奈川県川崎市高津区久地2-13-36",
      extractor.send(:clean_address, "神奈川県川崎市高津区久地2-13-36 事業所：〒252-0328 神奈川県相模原市南区麻溝台3062-1")
    )
    assert_equal(
      "福岡県福岡市博多区奈良屋町11-6 NS奈良屋ビル5F",
      extractor.send(:clean_address, "福岡県福岡市博多区奈良屋町11-6 NS奈良屋ビル5F・北九州支店〒800-0236福岡県北九州市小倉南区下貫1-7-18-1F")
    )
    assert_equal(
      "香川県高松市朝日新町23-19",
      extractor.send(:clean_address, "香川県高松市朝日新町23-19 高松支店：〒760-0064 香川県高松市朝日新町23-19")
    )
  end

  test "clean_address removes second office after label colon" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "福島県相馬郡新地町谷地小屋字南狼沢4-67",
      extractor.send(:clean_address, "福島県相馬郡新地町谷地小屋字南狼沢4-67 栃木営業所：　栃木県真岡市久下田西6-2-2")
    )
  end

  test "clean_address removes postal mark after inferred prefecture" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "福岡県北九州市八幡東区平野二丁目11番1号",
      extractor.send(:clean_address, "福岡県〒805－8528 北九州市八幡東区平野二丁目11番1号")
    )
  end

  test "clean_address removes bracketed and slash office tails" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "佐賀県武雄市北方町大字大崎1100-8",
      extractor.send(:clean_address, "佐賀県武雄市北方町大字大崎1100-8 [佐賀支店]佐賀県佐賀市木原2丁目22-23")
    )
    assert_equal(
      "福岡県大牟田市浄真町11番地",
      extractor.send(:clean_address, "福岡県大牟田市浄真町11番地　／　工場　福岡県大牟田市八江町65番地")
    )
  end

  test "clean_address removes site navigation tails" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "大阪府大阪市中央区島之内1丁目21-19 オリエンタル堺筋ビル8F AGUICHANT",
      extractor.send(:clean_address, "大阪府大阪市中央区島之内1丁目21-19 オリエンタル堺筋ビル8F AGUICHANT 購入ページ TOP 事業一覧")
    )
    assert_equal(
      "神奈川県川崎市高津区梶ケ谷6丁目17-4",
      extractor.send(:clean_address, "神奈川県川崎市高津区梶ケ谷6丁目17-4 Go to top ↑")
    )
    assert_equal(
      "東京都町田市鶴間3-4-1グランベリーパークセントラルコート3FL302",
      extractor.send(:clean_address, "東京都町田市鶴間3-4-1グランベリーパークセントラルコート3FL302代表小林大輝HOMEkeyboard_arrow_rightCOMPANY")
    )
    assert_equal(
      "埼玉県川口市鳩ヶ谷本町2-14-6",
      extractor.send(:clean_address, "埼玉県川口市鳩ヶ谷本町2-14-6 ホーム 会社紹介")
    )
    assert_equal(
      "埼玉県川口市鳩ヶ谷本町2-14-6",
      extractor.send(:clean_address, "埼玉県川口市鳩ヶ谷本町2-14-6 事務所")
    )
    assert_equal(
      "埼玉県入間郡毛呂山町目白台1-20-8",
      extractor.send(:clean_address, "埼玉県入間郡毛呂山町目白台1-20-8 READ MORE")
    )
    assert_equal(
      "埼玉県川越市 下赤坂1800-3",
      extractor.send(:clean_address, "埼玉県川越市 下赤坂1800-3芳野台工場 川越市芳野台1-103-17")
    )
  end

  test "clean_address removes store list tail" do
    extractor = CompanyInfoExtractor.new("")

    assert_equal(
      "神奈川県横浜市青葉区市ヶ尾町1737",
      extractor.send(:clean_address, "神奈川県横浜市青葉区市ヶ尾町1737 店　舗 市ヶ尾店・鴨志田店")
    )
  end
end
