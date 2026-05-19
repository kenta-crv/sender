require "test_helper"

class BrightData::WebEnricherTest < ActiveSupport::TestCase
  test "find_profile_link skips pdf company profile links" do
    html = <<~HTML
      <html>
        <body>
          <a href="/assets/docs/company_profile.pdf">会社概要PDF</a>
          <a href="/company/outline/">会社概要</a>
        </body>
      </html>
    HTML
    doc = Nokogiri::HTML(html)

    url = BrightData::WebEnricher.send(:find_profile_link, doc, "https://example.com/")

    assert_equal "https://example.com/company/outline/", url
  end

  test "find_profile_link skips sales company links" do
    html = <<~HTML
      <html>
        <body>
          <a href="/HANBAIGAISHA/index.html">販売会社</a>
          <a href="/COMPANY/gaiyou.html">会社概要</a>
        </body>
      </html>
    HTML
    doc = Nokogiri::HTML(html)

    url = BrightData::WebEnricher.send(:find_profile_link, doc, "https://example.com/")

    assert_equal "https://example.com/COMPANY/gaiyou.html", url
  end

  test "find_profile_link accepts nested company outline paths" do
    html = <<~HTML
      <html>
        <body>
          <a href="/COMPANY/gaiyou.html">役員新体制について</a>
        </body>
      </html>
    HTML
    doc = Nokogiri::HTML(html)

    url = BrightData::WebEnricher.send(:find_profile_link, doc, "https://example.com/")

    assert_equal "https://example.com/COMPANY/gaiyou.html", url
  end

  test "find_profile_link accepts corporate overview paths" do
    html = <<~HTML
      <html>
        <body>
          <a href="/corporate/overview">Overview</a>
        </body>
      </html>
    HTML
    doc = Nokogiri::HTML(html)

    url = BrightData::WebEnricher.send(:find_profile_link, doc, "https://example.com/")

    assert_equal "https://example.com/corporate/overview", url
  end

  test "find_profile_link uses image alt text on navigation buttons" do
    html = <<~HTML
      <html>
        <body>
          <a href="/Cinfo.html"><img src="/image/headIcon5.jpg" alt="会社情報"></a>
        </body>
      </html>
    HTML
    doc = Nokogiri::HTML(html)

    url = BrightData::WebEnricher.send(:find_profile_link, doc, "https://example.com/")

    assert_equal "https://example.com/Cinfo.html", url
  end

  test "resolve_contact_url ignores plain top page links" do
    assert_nil BrightData::WebEnricher.send(:resolve_contact_url, "https://example.com/", "https://example.com/")
    assert_equal "https://example.com/#contact", BrightData::WebEnricher.send(:resolve_contact_url, "https://example.com/#contact", "https://example.com/")
  end

  test "resolve_contact_url ignores mail and telephone links" do
    assert_nil BrightData::WebEnricher.send(:resolve_contact_url, "mailto:info@example.com", "https://example.com/company/")
    assert_nil BrightData::WebEnricher.send(:resolve_contact_url, "tel:03-1234-5678", "https://example.com/company/")
  end

  test "normalize_company removes job department suffixes" do
    base = BrightData::WebEnricher.send(:normalize_company, "ドライバーズサポート株式会社")

    assert_equal base, BrightData::WebEnricher.send(:normalize_company, "ドライバーズサポート株式会社宅配課")
    assert_equal base, BrightData::WebEnricher.send(:normalize_company, "業務委託 ドライバーズサポート株式会社/関西支店宅配課")
  end

  test "normalize_company treats curly apostrophes as punctuation" do
    assert_equal(
      BrightData::WebEnricher.send(:normalize_company, "株式会社Age's"),
      BrightData::WebEnricher.send(:normalize_company, "株式会社Age’s")
    )
  end

  test "normalize_company keeps company names ending in store and normalizes sharyo variants" do
    assert_equal "廣嶋建材店", BrightData::WebEnricher.send(:normalize_company, "有限会社廣嶋建材店")
    assert_equal(
      BrightData::WebEnricher.send(:normalize_company, "株式会社東京車輛"),
      BrightData::WebEnricher.send(:normalize_company, "東京車輌株式会社")
    )
  end

  test "normalized_customer_candidates keeps romanized silent e variants" do
    candidates = BrightData::WebEnricher.send(:normalized_customer_candidates, "合同会社NO Limite")

    assert_includes candidates, "nolimite"
    assert_includes candidates, "nolimit"
  end

  test "company_match avoids short generic suffix matches" do
    assert BrightData::WebEnricher.send(:company_match?, "シエル志免センタ", "シエル")
    assert BrightData::WebEnricher.send(:company_match?, "会社概要企業情報佐藤食品", "佐藤食品")
    refute BrightData::WebEnricher.send(:company_match?, "ブックスペス", "スペス")
  end

  test "extract_page_company prefers labeled company name before footer noise" do
    doc = Nokogiri::HTML(<<~HTML)
      <html>
        <head><title>会社概要 - 食品原料用ミルクパウダーの製造販売元</title></head>
        <body>
          <table>
            <tr><th>社名</th><td>東神商事株式会社</td></tr>
          </table>
          <footer>Copyright©TOSHIN CO.,LTD All Rights Reserved.</footer>
        </body>
      </html>
    HTML

    assert_equal "東神商事株式会社", BrightData::WebEnricher.send(:extract_page_company, doc)
  end

  test "extract_corp_name keeps bracketed company name before recruit wording" do
    assert_equal(
      "株式会社SA",
      BrightData::WebEnricher.send(:extract_corp_name, "【株式会社SA】配達/配送の求人情報 | 軽貨物運送事業")
    )
  end

  test "enrich_from_url accepts customer name in body when page company is css noise" do
    customer = Customer.new(company: "東神商事株式会社")
    extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <head><title>widthEqualsCo</title></head>
        <body>
          <script>#{"var css = 'widthEqualsCo';" * 500}</script>
          <p>社名 東神商事株式会社</p>
          <p>所在地 本社 〒103-0026 東京都中央区日本橋兜町17-1 日本橋ロイヤルプラザ621</p>
          <p>TEL:03-3664-3031</p>
        </body>
      </html>
    HTML

    with_singleton_method(CompanyInfoExtractor, :fetch_and_parse, ->(_url, customer: nil) { extractor }) do
      result = BrightData::WebEnricher.enrich_from_url("https://www.mil-knack.co.jp/company/", customer)

      assert_equal true, result[:matched]
      assert_equal "03-3664-3031", result[:tel]
      assert_equal "東京都中央区日本橋兜町17-1 日本橋ロイヤルプラザ621", result[:address]
    end
  end

  test "enrich_from_url accepts page company mismatch when title contains romanized customer alias" do
    customer = Customer.new(company: "合同会社NO Limite")
    extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <head><title>合同会社ノーリミット - 配送のことなら 合同会社Nolimit</title></head>
        <body>
          <h1>合同会社ノーリミット</h1>
          <p>〒136-0071 東京都江東区亀戸7-32-6 亀戸ハウス4号室 TEL:080-4031-1797</p>
          <a href="/contact">お問い合わせ</a>
        </body>
      </html>
    HTML

    with_singleton_method(CompanyInfoExtractor, :fetch_and_parse, ->(_url, customer: nil) { extractor }) do
      result = BrightData::WebEnricher.enrich_from_url("https://nolimit-tokyo.com/", customer)

      assert_equal true, result[:matched]
      assert_equal "080-4031-1797", result[:tel]
      assert_equal "東京都江東区亀戸7-32-6 亀戸ハウス4号室", result[:address]
    end
  end

  test "enrich_from_url does not follow host profile when mismatch match comes from article title" do
    customer = Customer.new(company: "NEO LEAP")
    top_extractor = Struct.new(:doc, :extract).new(
      Nokogiri::HTML(<<~HTML),
        <html>
          <head><title>NEO LEAP customer story</title></head>
          <body>
            <h1>NEO LEAP interview</h1>
            <a href="/company/">Company profile</a>
            <footer>Copyright YourRoot Inc.</footer>
          </body>
        </html>
      HTML
      { tel: nil, address: nil, contact_url: nil, company: nil }
    )
    host_profile = Struct.new(:doc, :extract).new(
      Nokogiri::HTML("<html><body><h1>YourRoot Inc.</h1></body></html>"),
      { tel: "045-565-9020", address: "Kanagawa Yokohama", contact_url: nil, company: "YourRoot Inc." }
    )
    calls = []

    with_singleton_method(CompanyInfoExtractor, :fetch_and_parse, ->(url, customer: nil) do
      calls << url
      url.end_with?("/company/") ? host_profile : top_extractor
    end) do
      with_singleton_method(CompanyInfoExtractor, :fetch_and_parse_rendered, ->(_url, customer: nil) { nil }) do
        result = BrightData::WebEnricher.enrich_from_url("https://yourroot.example/news/neo-leap", customer)

        assert_equal true, result[:matched]
        assert_nil result[:tel]
        assert_nil result[:address]
        assert_equal "https://yourroot.example/news/neo-leap", result[:source_url]
        assert_equal ["https://yourroot.example/news/neo-leap"], calls
      end
    end
  end

  test "enrich_from_url keeps current page when it already has tel and address" do
    customer = Customer.new(company: "佐藤食品株式会社")
    top_extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <head><title>会社概要｜企業情報｜佐藤食品株式会社</title></head>
        <body>
          <h1>会社概要</h1>
          <a href="/company/">会社概要</a>
          <p>〒824-0002 福岡県行橋市東大橋4丁目1570-1 Google map</p>
          <p>TEL：0930-23-0865（代表）</p>
        </body>
      </html>
    HTML
    unused_profile = CompanyInfoExtractor.new("")
    calls = []

    with_singleton_method(CompanyInfoExtractor, :fetch_and_parse, ->(url, customer: nil) do
      calls << url
      url.end_with?("/company/") ? unused_profile : top_extractor
    end) do
      result = BrightData::WebEnricher.enrich_from_url("https://www.satou-shokuhin.co.jp/company/outline/", customer)

      assert_equal "0930-23-0865", result[:tel]
      assert_equal "福岡県行橋市東大橋4丁目1570-1", result[:address]
      assert_equal "https://www.satou-shokuhin.co.jp/company/outline/", result[:source_url]
      assert_equal ["https://www.satou-shokuhin.co.jp/company/outline/"], calls
    end
  end

  test "enrich_from_url prioritizes company overview page over top page footer data" do
    customer = Customer.new(company: "Example Logistics")
    top_extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <head><title>Example Logistics</title></head>
        <body>
          <h1>Example Logistics</h1>
          <a href="/company/">会社概要</a>
          <footer>
            <p>〒105-0011 東京都港区芝公園1-1-1</p>
            <p>TEL：03-1111-1111</p>
          </footer>
        </body>
      </html>
    HTML
    profile_extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <body>
          <h1>会社概要</h1>
          <dl>
            <dt>社名</dt><dd>Example Logistics</dd>
            <dt>本社所在地</dt><dd>東京都港区芝5-5-5</dd>
          </dl>
          <p>TEL：03-5555-5555</p>
          <a href="/contact/">お問い合わせ</a>
        </body>
      </html>
    HTML
    calls = []

    with_singleton_method(CompanyInfoExtractor, :fetch_and_parse, ->(url, customer: nil) do
      calls << url
      url.end_with?("/company/") ? profile_extractor : top_extractor
    end) do
      result = BrightData::WebEnricher.enrich_from_url("https://example-logistics.test/", customer)

      assert_equal "03-5555-5555", result[:tel]
      assert_equal "東京都港区芝5-5-5", result[:address]
      assert_equal "https://example-logistics.test/contact/", result[:contact_url]
      assert_equal "https://example-logistics.test/company/", result[:source_url]
      assert_equal ["https://example-logistics.test/", "https://example-logistics.test/company/"], calls
    end
  end

  test "enrich_from_url keeps top page company overview section when present" do
    customer = Customer.new(company: "Example Logistics")
    top_extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <head><title>Example Logistics</title></head>
        <body>
          <a href="/company/">会社概要</a>
          <section>
            <h2>会社概要</h2>
            <dl>
              <dt>社名</dt><dd>Example Logistics</dd>
              <dt>所在地</dt><dd>東京都港区芝2-2-2</dd>
              <dt>TEL</dt><dd>03-2222-2222</dd>
            </dl>
          </section>
        </body>
      </html>
    HTML
    other_profile = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html><body>東京都港区芝9-9-9 TEL：03-9999-9999</body></html>
    HTML
    calls = []

    with_singleton_method(CompanyInfoExtractor, :fetch_and_parse, ->(url, customer: nil) do
      calls << url
      url.end_with?("/company/") ? other_profile : top_extractor
    end) do
      result = BrightData::WebEnricher.enrich_from_url("https://example-logistics.test/", customer)

      assert_equal "03-2222-2222", result[:tel]
      assert_equal "東京都港区芝2-2-2", result[:address]
      assert_equal "https://example-logistics.test/", result[:source_url]
      assert_equal ["https://example-logistics.test/"], calls
    end
  end

  test "enrich_from_url keeps searching when current page only has address" do
    customer = Customer.new(company: "Example Logistics")
    top_extractor = Struct.new(:doc, :extract).new(
      Nokogiri::HTML(<<~HTML),
        <html>
          <head><title>Example Logistics</title></head>
          <body>
            <h1>Example Logistics</h1>
            <a href="/company/profile/">Company profile</a>
          </body>
        </html>
      HTML
      { tel: nil, address: "東京都港区芝5-1-1", contact_url: nil, company: "Example Logistics" }
    )
    profile_extractor = Struct.new(:doc, :extract).new(
      Nokogiri::HTML("<html><body><h1>Example Logistics</h1></body></html>"),
      { tel: "03-1234-5678", address: "東京都港区芝9-9-9", contact_url: "/contact/", company: "Example Logistics" }
    )
    calls = []

    with_singleton_method(CompanyInfoExtractor, :fetch_and_parse, ->(url, customer: nil) do
      calls << url
      url.end_with?("/company/profile/") ? profile_extractor : top_extractor
    end) do
      result = BrightData::WebEnricher.enrich_from_url("https://example-logistics.test/", customer)

      assert_equal "03-1234-5678", result[:tel]
      assert_equal "東京都港区芝9-9-9", result[:address]
      assert_equal "https://example-logistics.test/contact/", result[:contact_url]
      assert_equal "https://example-logistics.test/company/profile/", result[:source_url]
      assert_equal ["https://example-logistics.test/", "https://example-logistics.test/company/profile/"], calls
    end
  end

  test "enrich_from_url uses head office data when a branch-specific page is not found" do
    customer = Customer.new(company: "株式会社シーエル 宇美東センター")
    top_extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <head><title>株式会社シーエル</title></head>
        <body>
          <p>株式会社シーエル本社</p>
          <p>〒812-0863 福岡県福岡市博多区金の隈3丁目14番3号CL会館</p>
          <p>TEL:092-504-1708</p>
        </body>
      </html>
    HTML

    with_singleton_method(CompanyInfoExtractor, :fetch_and_parse, ->(_url, customer: nil) { top_extractor }) do
      with_singleton_method(CompanyInfoExtractor, :fetch_and_parse_rendered, ->(_url, customer: nil) { nil }) do
      result = BrightData::WebEnricher.enrich_from_url("https://www.cl-gp.co.jp/introduction/", customer)

      assert_equal "092-504-1708", result[:tel]
      assert_equal "福岡県福岡市博多区金の隈3丁目14番3号CL会館", result[:address]
      end
    end
  end

  test "branch match requires the most specific locality when current address has a ward" do
    customer = Customer.new(
      company: "株式会社マリンブルー 横浜戸塚デリバリーステーション",
      address: "神奈川県 横浜市 戸塚区"
    )
    doc = Nokogiri::HTML("<html><body>株式会社マリンブルー 横浜市港北区新横浜1-3-1</body></html>")

    refute BrightData::WebEnricher.send(
      :branch_match_safe?,
      doc,
      customer,
      address: "神奈川県横浜市港北区新横浜1-3-1"
    )
  end

  test "enrich_from_url accepts branch locality data on introduction pages" do
    customer = Customer.new(
      company: "株式会社シーエル 筑紫野三井センター",
      address: "福岡県 筑紫野市 桜台駅 徒歩8分"
    )
    top_extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <head><title>事業所紹介 | 株式会社シーエル</title></head>
        <body>
          <p>株式会社シーエル</p>
          <a href="/about/">会社概要</a>
          <p>配送センター 〒816-0062 福岡市博多区立花寺1-7-1 TEL:092-504-7515</p>
          <p>筑紫野センター 〒818-0065 福岡県筑紫野市大字諸田174-2 TEL:092-919-7830FAX:092-919-7831</p>
        </body>
      </html>
    HTML
    calls = []

    with_singleton_method(CompanyInfoExtractor, :fetch_and_parse, ->(url, customer: nil) do
      calls << url
      top_extractor
    end) do
      result = BrightData::WebEnricher.enrich_from_url("https://www.cl-gp.co.jp/introduction/", customer)

      assert_equal "092-919-7830", result[:tel]
      assert_equal "福岡県筑紫野市大字諸田174-2", result[:address]
      assert_equal ["https://www.cl-gp.co.jp/introduction/"], calls
    end
  end

  test "enrich_from_url treats business suffix warehouse as company name noise" do
    customer = Customer.new(
      company: "株式会社博運社倉庫",
      address: "福岡県 粕屋町 柚須駅 徒歩20分"
    )
    extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <head><title>会社概要 | 株式会社博運社</title></head>
        <body>
          <h1>会社概要</h1>
          <table>
            <tr><th>会社名</th><td>株式会社博運社</td></tr>
            <tr><th>本社所在地</th><td>〒811-2233 福岡県糟屋郡志免町別府北3丁目4番1号 TEL：092-621-8831</td></tr>
          </table>
          <a href="/otoiawase/">お問い合わせ</a>
        </body>
      </html>
    HTML

    with_singleton_method(CompanyInfoExtractor, :fetch_and_parse, ->(_url, customer: nil) { extractor }) do
      result = BrightData::WebEnricher.enrich_from_url("https://www.hus.co.jp/kaisyaannai/kaishagaiyo/", customer)

      assert_equal "092-621-8831", result[:tel]
      assert_equal "福岡県糟屋郡志免町別府北3丁目4番1号", result[:address]
    end
  end

  test "enrich_from_url renders common profile candidates when static html has no data" do
    customer = Customer.new(company: "株式会社ディーバ")
    top_extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <head><title>株式会社ディーバ</title></head>
        <body><h1>DIVA</h1></body>
      </html>
    HTML
    static_candidate = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <head>
          <title>会社概要 | 株式会社ディーバ</title>
          <meta name="description" content="株式会社ディーバの会社概要">
        </head>
        <body>株式会社ディーバ</body>
      </html>
    HTML
    rendered_candidate = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <body>
          <h1>会社概要</h1>
          <p>社名 株式会社ディーバ</p>
          <p>所在地 新宿本社 〒163-1343 東京都新宿区西新宿六丁目5番1号 新宿アイランドタワー42階・43階 Tel：03-5909-5177(代表)</p>
        </body>
      </html>
    HTML

    with_singleton_method(CompanyInfoExtractor, :fetch_and_parse, ->(url, customer: nil) do
      url == "https://www.diva.co.jp/" ? top_extractor : static_candidate
    end) do
      with_singleton_method(CompanyInfoExtractor, :fetch_and_parse_rendered, ->(url, customer: nil) do
        rendered_candidate
      end) do
        result = BrightData::WebEnricher.enrich_from_url("https://www.diva.co.jp/", customer)

        assert_equal "03-5909-5177", result[:tel]
        assert_equal "東京都新宿区西新宿六丁目5番1号 新宿アイランドタワー42階・43階", result[:address]
      end
    end
  end

  test "enrich_from_url ignores studio metadata prose and uses rendered headquarters address" do
    customer = Customer.new(company: "松下運送")
    static_extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <head><title>会社情報｜松下運送株式会社</title></head>
        <body>
          <script type="application/json">
            {"description":"大阪府寝屋川市にある松下運送は創業60年以上の実績を持ち、安全・確実・信頼の運送サービスを提供。建設現場に特化し、特殊物の運搬も行います"}
          </script>
        </body>
      </html>
    HTML
    rendered_extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <body>
          <h1>会社概要</h1>
          <dl>
            <dt>社名</dt><dd>松下運送株式会社</dd>
            <dt>本社所在地</dt><dd>大阪府寝屋川市仁和寺本町5丁目2番17号</dd>
          </dl>
          <p>TEL：072-838-1371</p>
          <a href="/contact">お問い合わせ</a>
        </body>
      </html>
    HTML

    with_singleton_method(CompanyInfoExtractor, :fetch_and_parse, ->(_url, customer: nil) { static_extractor }) do
      with_singleton_method(CompanyInfoExtractor, :fetch_and_parse_rendered, ->(_url, customer: nil) { rendered_extractor }) do
        result = BrightData::WebEnricher.enrich_from_url("https://matsushita-unso.com/company", customer)

        assert_equal "072-838-1371", result[:tel]
        assert_equal "大阪府寝屋川市仁和寺本町5丁目2番17号", result[:address]
        assert_equal "https://matsushita-unso.com/contact", result[:contact_url]
      end
    end
  end

  test "enrich_from_url rejects a different company page even when customer name appears in body text" do
    customer = Customer.new(company: "Logic Connect Inc.")
    extractor = CompanyInfoExtractor.new(<<~HTML, customer: customer)
      <html>
        <head><title>Keipe Connect Inc.</title></head>
        <body>
          <h1>About Keipe Connect Inc.</h1>
          <p>Past article: Logic Connect Inc. was mentioned as a related search term.</p>
          <p>Address: Yamanashi 1-1-1</p>
        </body>
      </html>
    HTML

    with_singleton_method(CompanyInfoExtractor, :fetch_and_parse, ->(_url, customer: nil) { extractor }) do
      result = BrightData::WebEnricher.enrich_from_url("https://keipe-connect.example/about/", customer)

      assert_equal false, result[:matched]
    end
  end

  private

  def with_singleton_method(klass, method_name, replacement)
    original = klass.method(method_name)
    klass.define_singleton_method(method_name, &replacement)
    yield
  ensure
    klass.define_singleton_method(method_name) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end
end
