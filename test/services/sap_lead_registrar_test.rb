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

  def resolved_posting(job_key, official_url:)
    JobPosting.create!(
      source: "kyujinbox",
      company_raw: "株式会社テスト",
      company_clean: "テスト",
      title: "SAPコンサルタント",
      area: "東京都",
      official_name: "株式会社テスト",
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
