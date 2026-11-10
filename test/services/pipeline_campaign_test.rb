require "test_helper"

class PipelineCampaignTest < ActiveSupport::TestCase
  test "sales keywords become a kyujinbox url for every prefecture and do not filter titles or dispatch jobs" do
    campaign = Pipeline::Campaign.find("okurite_sales")
    url = campaign.start_urls.first

    assert_equal 9 * 47, campaign.start_urls.size
    assert_includes url, "%E6%B3%95%E4%BA%BA%E5%96%B6%E6%A5%AD"
    assert_includes url, "-%E5%8C%97%E6%B5%B7%E9%81%93"
    assert_includes campaign.start_urls[1], "-%E9%9D%92%E6%A3%AE%E7%9C%8C"
    assert_includes campaign.start_urls[46], "-%E6%B2%96%E7%B8%84%E7%9C%8C"
    assert_includes url, "?u=1"
    assert_equal 9 * 47, campaign.historical_urls.size
    refute_includes campaign.historical_urls.first, "u=1"
    assert_equal true, campaign.exclude_existing_clients?
    assert_equal 100, campaign.serp_daily_limit

    page = Kyujinbox::Parser.extract(<<~HTML, page_url: url, exclude_words: campaign.exclude_words)
      <section class="p-result_card">
        <a class="p-result_title_link" href="/jbn/sales1"></a>
        <span class="p-result_name">一般事務</span>
        <p class="p-result_companyName">株式会社営業先</p>
      </section>
      <section class="p-result_card">
        <a class="p-result_title_link" href="/jbn/sales2"></a>
        <span class="p-result_name">派遣スタッフ</span>
        <p class="p-result_companyName">株式会社人材派遣</p>
      </section>
    HTML
    assert_equal %w[jbn:sales1 jbn:sales2], page.postings.map(&:job_key)
  end

  test "a sales import keeps the campaign and a dispatch company" do
    campaign = Pipeline::Campaign.find("okurite_sales")
    html = <<~HTML
      <section class="p-result_card">
        <a class="p-result_title_link" href="/jbn/keep1"></a>
        <span class="p-result_name">一般事務</span>
        <p class="p-result_companyName">株式会社営業先</p>
      </section>
    HTML
    client = Object.new
    client.define_singleton_method(:get) { |_url| html }
    stats = Kyujinbox::Importer.new(client: client, page_interval: 0, campaign: campaign).run(
      start_urls: [campaign.start_urls.first],
      max_pages: 1
    )

    posting = JobPosting.find_by!(job_key: "jbn:keep1")
    assert_equal 1, stats[:created]
    assert_equal "okurite_sales", posting.campaign_key
    assert_equal "new", posting.status
  end

  test "sales send targets skip an existing client by company name or domain" do
    Client.create!(email: "client-a@example.test", password: "password1", company: "株式会社既存顧客", domain: "existing.example")
    own = Customer.create!(company: "株式会社既存顧客", business: "営業代行", contact_url: "https://existing.example/contact", url: "https://existing.example")
    same_domain = Customer.create!(company: "別会社株式会社", business: "営業代行", contact_url: "https://form.example/contact", url: "https://www.existing.example/about")
    other = Customer.create!(company: "株式会社対象", business: "営業代行", contact_url: "https://target.example/contact", url: "https://target.example")

    ids = Pipeline::SendTargets.new(Pipeline::Campaign.find("okurite_sales")).ids

    assert_includes ids, other.id
    refute_includes ids, own.id
    refute_includes ids, same_domain.id
  end

  test "campaign url replaces the submission url for the click target and the link host" do
    job = FormSendJob.new
    batch = FormSubmissionBatch.new(campaign_key: "okurite_sales")
    submission = Submission.new(url: "https://j-work.jp/sap/")

    assert_equal "https://okurite.pro/sales", job.send(:tracking_destination, batch, submission)
    assert_equal "okurite.pro", job.send(:production_link_options, "https://okurite.pro/sales")[:host]
    assert_equal "https://j-work.jp/sap/", job.send(:tracking_destination, FormSubmissionBatch.new, submission)
  end
end
