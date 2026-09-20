require "test_helper"

class CustomerTest < ActiveSupport::TestCase
  test "with_legal_entity matches companies with legal entity designators" do
    corp = Customer.create!(company: "株式会社テスト", tel: "03-0000-0000")
    sole = Customer.create!(company: "田中商店", tel: "03-0000-0001")

    ids = Customer.with_legal_entity.pluck(:id)

    assert_includes ids, corp.id
    refute_includes ids, sole.id
  end

  test "serp_extraction_targets excludes companies without legal entity designators" do
    corp = Customer.create!(company: "有限会社サンプル", url: nil, serp_status: nil)
    sole = Customer.create!(company: "個人商店", url: nil, serp_status: nil)

    ids = Customer.serp_extraction_targets.pluck(:id)

    assert_includes ids, corp.id
    refute_includes ids, sole.id
  end

  test "cleanup_duplicates! keeps lowest id and deletes excess contact_url rows" do
    url = "https://example.test/contact"
    keep = Customer.create!(company: "株式会社残す", contact_url: url)
    drop1 = Customer.create!(company: "株式会社消す1", contact_url: url)
    drop2 = Customer.create!(company: "株式会社消す2", contact_url: url)
    other = Customer.create!(company: "株式会社別URL", contact_url: "https://other.test/contact")

    deleted = Customer.cleanup_duplicates!(attribute: "contact_url", scope: Customer.all)

    assert_equal 2, deleted
    assert Customer.exists?(keep.id)
    refute Customer.exists?(drop1.id)
    refute Customer.exists?(drop2.id)
    assert Customer.exists?(other.id)
  end

  test "filter_by_last_form_call keeps unsent and matching last form calls in SQL" do
    unsent = Customer.create!(company: "未送信", tel: "03-0000-1000")
    success = Customer.create!(company: "成功", tel: "03-0000-1001")
    failure = Customer.create!(company: "失敗", tel: "03-0000-1002")
    Call.create!(customer: success, call_type: "form", status: "自動送信成功", created_at: 2.days.ago)
    Call.create!(customer: failure, call_type: "form", status: "自動送信失敗", created_at: 2.days.ago)

    ids = Customer.filter_by_last_form_call(
      status: ["自動送信成功"],
      calls_id_null: "true"
    ).pluck(:id)

    assert_includes ids, unsent.id
    assert_includes ids, success.id
    refute_includes ids, failure.id
  end
end
