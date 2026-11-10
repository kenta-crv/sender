require "test_helper"

class KyujinboxBackfillTest < ActiveSupport::TestCase
  SAP_URL = "https://xn--pckua2a7gp15o89zb.com/SAP%E3%81%AE%E4%BB%95%E4%BA%8B".freeze
  S4_URL = "https://xn--pckua2a7gp15o89zb.com/S4HANA%E3%81%AE%E4%BB%95%E4%BA%8B".freeze

  test "backfill urls are the full lists without the new-arrival flag" do
    urls = Kyujinbox.backfill_urls
    assert_equal [SAP_URL, S4_URL], urls
    assert urls.none? { |url| url.include?("u=1") }
  end

  test "one run stops at the page budget, waits three seconds, and the next run continues" do
    pages = {
      SAP_URL => card("jbn:p1", "株式会社いち", next_href: "?pg=2"),
      "#{SAP_URL}?pg=2" => card("jbn:p2", "株式会社に", next_href: "?pg=3"),
      "#{SAP_URL}?pg=3" => card("jbn:p3", "株式会社さん", next_href: nil),
      S4_URL => card("jbn:s1", "株式会社よん", next_href: nil) + dispatch_card
    }
    client = PageClient.new(pages)
    backfill = Kyujinbox::Backfill.new(client: client, page_interval: 3)
    importer = backfill.instance_variable_get(:@importer)
    slept = []
    importer.define_singleton_method(:sleep) { |seconds| slept << seconds }

    first = backfill.run(max_pages: 2)

    assert_equal 2, first[:pages]
    assert_equal 2, first[:created]
    assert_equal [3], slept
    cursor = KyujinboxBackfillCursor.find_by!(start_url: SAP_URL)
    assert_equal false, cursor.finished
    assert_equal "page_limit", cursor.stop_reason
    assert_equal "#{SAP_URL}?pg=3", cursor.next_url
    assert_equal 2, cursor.pages_read
    assert_nil KyujinboxBackfillCursor.find_by(start_url: S4_URL)

    second = Kyujinbox::Backfill.new(client: client, page_interval: 0).run(max_pages: 2)

    assert_equal 2, second[:pages]
    assert_equal 2, second[:created]
    assert_equal true, KyujinboxBackfillCursor.find_by!(start_url: SAP_URL).finished
    s4 = KyujinboxBackfillCursor.find_by!(start_url: S4_URL)
    assert_equal true, s4.finished
    assert_equal "last_page", s4.stop_reason
    assert_equal %w[jbn:p1 jbn:p2 jbn:p3 jbn:s1], JobPosting.order(:id).pluck(:job_key)
    assert_equal ["new"], JobPosting.distinct.pluck(:status)
  end

  private

  def card(key, company, next_href:)
    href = key.sub("jbn:", "/jbn/")
    next_link = next_href.present? ? %(<a class="c-pager_btn--next" href="#{next_href}">次へ</a>) : ""
    <<~HTML
      <section class="p-result_card">
        <a class="p-result_title_link" href="#{href}"></a>
        <span class="p-result_name">SAPコンサルタント</span>
        <p class="p-result_companyName">#{company}</p>
      </section>
      #{next_link}
    HTML
  end

  def dispatch_card
    <<~HTML
      <section class="p-result_card">
        <a class="p-result_title_link" href="/jbn/disp"></a>
        <span class="p-result_name">派遣スタッフ</span>
        <p class="p-result_companyName">株式会社派遣</p>
      </section>
    HTML
  end

  class PageClient
    def initialize(pages)
      @pages = pages
    end

    def get(url)
      @pages.fetch(url)
    end
  end
end
