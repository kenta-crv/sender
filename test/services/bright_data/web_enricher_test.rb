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

  test "company_match avoids short generic suffix matches" do
    assert BrightData::WebEnricher.send(:company_match?, "シエル志免センタ", "シエル")
    assert BrightData::WebEnricher.send(:company_match?, "会社概要企業情報佐藤食品", "佐藤食品")
    refute BrightData::WebEnricher.send(:company_match?, "ブックスペス", "スペス")
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
      assert_equal "東京都港区芝5-1-1", result[:address]
      assert_equal "https://example-logistics.test/contact/", result[:contact_url]
      assert_equal "https://example-logistics.test/company/profile/", result[:source_url]
      assert_equal ["https://example-logistics.test/", "https://example-logistics.test/company/profile/"], calls
    end
  end

  test "enrich_from_url does not use head office data for unmatched branch rows" do
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

      assert_nil result[:tel]
      assert_nil result[:address]
      end
    end
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
