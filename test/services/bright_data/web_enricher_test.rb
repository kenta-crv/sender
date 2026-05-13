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
      assert_equal ["https://www.satou-shokuhin.co.jp/company/outline/"], calls
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
