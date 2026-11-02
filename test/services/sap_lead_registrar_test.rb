require "test_helper"

class SapLeadRegistrarTest < ActiveSupport::TestCase
  test "normalized names match across legal entity position and width" do
    left = Customer.normalized_name("株式会社テスト")
    right = Customer.normalized_name("テスト株式会社")

    assert Customer.name_similarity?(left, right)
    refute Customer.name_similarity?(left, Customer.normalized_name("株式会社別会社"))
  end

  test "appends SAP to an existing company and keeps its url" do
    existing = Customer.create!(company: "株式会社テスト", business: "情報通信", url: "https://already.example")
    posting = resolved_posting("jbn:reg-existing", official_url: "https://new.example")

    stats = SapLead::Registrar.new.run

    existing.reload
    posting.reload
    assert_equal 1, stats[:appended]
    assert_equal "情報通信,SAP", existing.business
    assert_equal "https://already.example", existing.url
    assert_equal "registered", posting.status
    assert_equal "appended", posting.registration_kind
    assert_equal existing.id, posting.customer_id
    vars = JSON.parse(existing.template_vars)
    assert_equal "SAPコンサルタント", vars["job_title"]
  end

  test "reuses one finder so the second posting of the same company is appended" do
    first = resolved_posting("jbn:reg-once", official_url: "https://once.example", company: "株式会社一回")
    second = resolved_posting("jbn:reg-twice", official_url: "https://once.example/jp/about", company: "株式会社一回")

    stats = SapLead::Registrar.new.run

    assert_equal 1, stats[:created]
    assert_equal 1, stats[:appended]
    assert_equal 1, Customer.where(company: "株式会社一回").count
    assert_equal "created", first.reload.registration_kind
    assert_equal "appended", second.reload.registration_kind
    assert_equal first.customer_id, second.customer_id
  end

  test "a later posting matches the url filled on the earlier customer" do
    first = resolved_posting("jbn:reg-url-a", official_url: "https://filled.example", company: "株式会社甲")
    second = resolved_posting("jbn:reg-url-b", official_url: "https://www.filled.example/about", company: "株式会社乙")

    stats = SapLead::Registrar.new.run

    assert_equal 1, stats[:created]
    assert_equal 1, stats[:appended]
    assert_nil Customer.find_by(company: "株式会社乙")
    assert_equal first.reload.customer_id, second.reload.customer_id
  end

  test "name match on the earlier customer wins over a later domain match" do
    earlier = Customer.create!(company: "株式会社先", business: "製造")
    Customer.create!(company: "株式会社後", business: "製造", url: "https://later.example")
    finder = SapLead::DuplicateFinder.new

    found = finder.find(company: "株式会社先", url: "https://later.example")

    assert_equal earlier.id, found.id
  end

  test "creates a shared customer when none exists" do
    posting = resolved_posting("jbn:reg-new", official_url: "https://new.example")

    stats = SapLead::Registrar.new.run

    customer = Customer.find_by!(company: "株式会社テスト")
    assert_equal 1, stats[:created]
    assert_nil customer.client_id
    assert_equal "SAP", customer.business
    assert_equal "https://new.example", customer.url
    assert_equal "東京都千代田区1-1", customer.address
    assert_equal "registered", posting.reload.status
    assert_equal "created", posting.registration_kind
  end

  private

  def resolved_posting(job_key, official_url:, company: "株式会社テスト")
    JobPosting.create!(
      source: "kyujinbox",
      company_raw: company,
      company_clean: company,
      title: "SAPコンサルタント",
      area: "東京都",
      official_name: company,
      headquarters_address: "東京都千代田区1-1",
      official_url: official_url,
      job_key: job_key,
      status: "resolved",
      corporate_number: "1234567890123",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
  end
end
