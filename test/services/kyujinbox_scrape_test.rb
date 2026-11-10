require "test_helper"

class KyujinboxScrapeTest < ActiveSupport::TestCase
  START_URL = "https://xn--pckua2a7gp15o89zb.com/SAP%E3%81%AE%E4%BB%95%E4%BA%8B?u=1".freeze
  PAGE2_URL = "https://xn--pckua2a7gp15o89zb.com/SAP%E3%81%AE%E4%BB%95%E4%BA%8B?u=1&pg=2".freeze

  test "parser keeps legal entities and builds job keys from jbn and uaid" do
    page = Kyujinbox::Parser.extract(sample_html, page_url: START_URL)

    assert_equal PAGE2_URL, page.next_url
    keys = page.postings.map(&:job_key)
    assert_equal ["jbn:abc123", "uaid:uaid99", "jbi:item7"], keys
    kept = page.postings.first
    assert_equal "株式会社テスト", kept.company_raw
    assert_equal "テスト", kept.company_clean
    assert_equal "SAPエンジニア", kept.title
    assert_equal "東京都", kept.area
    assert_equal "正社員", kept.employ_type
    assert_equal "パーソルテンプスタッフ株式会社", page.postings[1].company_clean
    refute_includes page.postings.map(&:company_raw), "田中商店"
    refute_includes page.postings.map(&:company_raw), "合同会社アルファ"
  end

  test "a region after a slash or parenthesis is removed before the legal entity check" do
    assert_equal "パーソルテンプスタッフ株式会社", Kyujinbox.base_company_name("パーソルテンプスタッフ株式会社／東海")
    assert Kyujinbox.legal_entity?("パーソルテンプスタッフ株式会社／東海")
    assert_equal "パーソルテンプスタッフ株式会社", Kyujinbox.clean_company("パーソルテンプスタッフ株式会社／東海")
    assert_equal "テスト", Kyujinbox.clean_company("株式会社テスト（東京）")
    assert_equal "テスト", Kyujinbox.clean_company("株式会社テスト/大阪")
    refute Kyujinbox.legal_entity?("田中商店／東京")

    page = Kyujinbox::Parser.extract(<<~HTML, page_url: START_URL)
      <section class="p-result_card">
        <a class="p-result_title_link" href="/jbn/region1"></a>
        <span class="p-result_name">SAPエンジニア</span>
        <p class="p-result_companyName">パーソルテンプスタッフ株式会社／東海</p>
      </section>
    HTML
    assert_equal "パーソルテンプスタッフ株式会社", page.postings.first.company_raw
  end

  test "job key falls back to company and title" do
    assert_equal "jb:plain1", Kyujinbox.job_key_for("https://example.test/jb/plain1", "株式会社A", "職種")
    assert_equal "株式会社A職種", Kyujinbox.job_key_for("https://example.test/jobs/1", "株式会社A", "職種")
  end

  test "start urls come from sap pipeline config" do
    urls = Kyujinbox.start_urls
    assert_equal 2 * 47, urls.size
    assert urls.all? { |url| url.include?("?u=1") }
    assert_includes urls.first, "SAP"
    assert_includes urls.first, "-%E5%8C%97%E6%B5%B7%E9%81%93"
    assert urls.any? { |url| url.include?("S4HANA") }
  end

  test "imports new postings and drops the same company prefix in one run" do
    stats = Kyujinbox::Importer.new(client: fake_client(first_page_html), page_interval: 0).run(
      start_urls: [START_URL],
      max_pages: 1
    )

    assert_equal 1, stats[:created]
    assert_equal 1, stats[:dropped]
    assert_equal ["jbn:abc123"], JobPosting.pluck(:job_key)
    assert_equal "new", JobPosting.find_by!(job_key: "jbn:abc123").status
  end

  test "updates last seen at for a known job and skips a new job from a recent company" do
    known = JobPosting.create!(
      source: "kyujinbox",
      company_raw: "株式会社テスト",
      company_clean: "テスト",
      title: "古い求人",
      posting_url: "https://example.test/jbn/known",
      job_key: "jbn:known",
      first_seen_at: 10.days.ago,
      last_seen_at: 10.days.ago,
      status: "resolved"
    )
    html = <<~HTML
      <section class="p-result_card">
        <a class="p-result_title_link" href="/jbn/known"></a>
        <span class="p-result_name">古い求人</span>
        <p class="p-result_companyName">株式会社テスト</p>
      </section>
      <section class="p-result_card">
        <a class="p-result_title_link" href="/jbn/newer"></a>
        <span class="p-result_name">新しいSAP求人</span>
        <p class="p-result_companyName">株式会社テスト</p>
      </section>
    HTML

    stats = Kyujinbox::Importer.new(client: fake_client(html), page_interval: 0).run(
      start_urls: [START_URL],
      max_pages: 1
    )

    known.reload
    newer = JobPosting.find_by!(job_key: "jbn:newer")
    assert_equal "resolved", known.status
    assert_in_delta Time.current, known.last_seen_at, 5
    assert_equal "skipped", newer.status
    assert_equal "30日以内に処理済み", newer.skip_reason
    assert_equal 1, stats[:seen]
    assert_equal 1, stats[:skipped]
    assert_equal 0, stats[:created]
  end

  test "title keywords ignore width and case and do not match HANA alone" do
    assert Kyujinbox.title_relevant?("ＳＡＰ導入")
    assert Kyujinbox.title_relevant?("s/4hanaエンジニア")
    assert Kyujinbox.title_relevant?("S／4導入")
    assert Kyujinbox.title_relevant?("S4HANAコンサルタント")
    assert Kyujinbox.title_relevant?("abap開発")
    assert Kyujinbox.title_relevant?("Basis運用")
    refute Kyujinbox.title_relevant?("HANAコンサルタント")
    refute Kyujinbox.title_relevant?("一般事務")
  end

  test "skips a posting whose title is unrelated to SAP" do
    html = <<~HTML
      <section class="p-result_card">
        <a class="p-result_title_link" href="/jbn/plain"></a>
        <span class="p-result_name">一般事務</span>
        <p class="p-result_companyName">株式会社テスト</p>
      </section>
      <section class="p-result_card">
        <a class="p-result_title_link" href="/jbn/sap"></a>
        <span class="p-result_name">SAPエンジニア</span>
        <p class="p-result_companyName">株式会社テスト</p>
      </section>
    HTML

    stats = Kyujinbox::Importer.new(client: fake_client(html), page_interval: 0).run(
      start_urls: [START_URL],
      max_pages: 1
    )

    unrelated = JobPosting.find_by!(job_key: "jbn:plain")
    related = JobPosting.find_by!(job_key: "jbn:sap")
    assert_equal "skipped", unrelated.status
    assert_equal "SAP関連外", unrelated.skip_reason
    assert_equal "new", related.status
    assert_equal 1, stats[:skipped]
    assert_equal 1, stats[:created]
  end

  test "keeps crawling the next page when every posting on the page was already seen" do
    JobPosting.create!(
      source: "kyujinbox",
      company_raw: "株式会社テスト",
      company_clean: "テスト",
      title: "SAPエンジニア",
      posting_url: "#{START_URL}/jbn/abc123",
      job_key: "jbn:abc123",
      first_seen_at: 2.days.ago,
      last_seen_at: 2.days.ago,
      status: "new"
    )
    html = <<~HTML
      <section class="p-result_card">
        <a class="p-result_title_link" href="/jbn/abc123"></a>
        <span class="p-result_name">SAPエンジニア</span>
        <p class="p-result_companyName">株式会社テスト</p>
      </section>
      <a class="c-pager_btn--next" href="?u=1&amp;pg=2">次のページへ</a>
    HTML
    client = SequenceClient.new(START_URL => html, PAGE2_URL => "<html></html>")

    stats = Kyujinbox::Importer.new(client: client, page_interval: 0).run(start_urls: [START_URL])

    assert_equal [START_URL, PAGE2_URL], client.calls
    assert_equal 2, stats[:pages]
    assert_equal 1, stats[:seen]
    assert_equal 0, stats[:created]
  end

  test "a missing next page ends that search and the next start url still runs" do
    other_url = "https://xn--pckua2a7gp15o89zb.com/S4HANA%E3%81%AE%E4%BB%95%E4%BA%8B?u=1"
    sap_html = first_page_html + '<a class="c-pager_btn--next" href="?u=1&amp;pg=2">次のページへ</a>'
    other_html = <<~HTML
      <section class="p-result_card">
        <a class="p-result_title_link" href="/jbn/other1"></a>
        <span class="p-result_name">S/4HANAコンサルタント</span>
        <p class="p-result_companyName">株式会社べつの会社</p>
      </section>
    HTML
    client = MissingPageClient.new(START_URL => sap_html, other_url => other_html)

    stats = Kyujinbox::Importer.new(client: client, page_interval: 0).run(start_urls: [START_URL, other_url])

    assert_equal [START_URL, PAGE2_URL, other_url], client.calls
    assert_equal 2, stats[:pages]
    assert_equal 2, stats[:created]
    assert_equal %w[jbn:abc123 jbn:other1], JobPosting.order(:id).pluck(:job_key)
  end

  private

  def sample_html
    <<~HTML
      <section class="p-result_card">
        <a class="p-result_title_link" href="/jbn/abc123"></a>
        <span class="p-result_name">SAPエンジニア</span>
        <p class="p-result_companyName">株式会社テスト</p>
        <li class="p-result_area">東京都</li>
        <li class="p-result_employType">正社員</li>
      </section>
      <section class="p-result_card">
        <a class="p-result_title_link" href="/rd/?uaid=uaid99"></a>
        <span class="p-result_name">開発</span>
        <p class="p-result_companyName">パーソルテンプスタッフ株式会社</p>
        <li class="p-result_area">大阪府</li>
        <li class="p-result_employType">契約社員</li>
      </section>
      <section class="p-result_card">
        <a class="p-result_title_link" href="/jbi/item7"></a>
        <span class="p-result_name">導入</span>
        <p class="p-result_companyName">合同会社ベータ</p>
      </section>
      <section class="p-result_card">
        <p class="p-result_companyName">田中商店</p>
        <span class="p-result_name">事務</span>
      </section>
      <section class="p-result_card">
        <a class="p-result_title_link" href="/jb/disp1"></a>
        <span class="p-result_name">派遣社員募集</span>
        <p class="p-result_companyName">合同会社アルファ</p>
      </section>
      <a class="c-pager_btn--next" href="?u=1&amp;pg=2">次のページへ</a>
    HTML
  end

  def first_page_html
    <<~HTML
      <section class="p-result_card">
        <a class="p-result_title_link" href="/jbn/abc123"></a>
        <span class="p-result_name">SAPエンジニア</span>
        <p class="p-result_companyName">株式会社あいうえおかきくけこ</p>
      </section>
      <section class="p-result_card">
        <a class="p-result_title_link" href="/jbn/abc999"></a>
        <span class="p-result_name">別のSAP求人</span>
        <p class="p-result_companyName">株式会社あいうえおかきくけこ商会</p>
      </section>
    HTML
  end

  def fake_client(html)
    SequenceClient.new(START_URL => html)
  end

  class MissingPageClient
    attr_reader :calls

    def initialize(pages)
      @pages = pages
      @calls = []
    end

    def get(url)
      @calls << url
      page = @pages[url]
      raise Kyujinbox::Client::NotFound, url if page.nil?

      page
    end
  end

  class SequenceClient
    attr_reader :calls

    def initialize(pages)
      @pages = pages
      @calls = []
    end

    def get(url)
      @calls << url
      @pages.fetch(url)
    end
  end
end
