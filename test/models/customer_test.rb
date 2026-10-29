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

  test "serp_extraction_targets excludes paused companies" do
    paused = Customer.create!(company: "株式会社停止", url: nil, serp_status: "serp_paused")

    refute_includes Customer.serp_extraction_targets.pluck(:id), paused.id
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

  test "business list stores multiple industries separated by half-width commas" do
    customer = Customer.create!(company: "株式会社複数業種", business: "情報通信、 SAP，製造")

    assert_equal "情報通信,SAP,製造", customer.reload.business
    assert_equal %w[情報通信 SAP 製造], customer.business_list
  end

  test "add_business! appends a missing industry and does not duplicate it" do
    customer = Customer.create!(company: "株式会社業種追加", business: "情報通信")

    customer.add_business!("SAP")
    customer.add_business!("SAP")

    assert_equal "情報通信,SAP", customer.reload.business
  end

  test "with_business matches any listed industry and avoids partial names" do
    listed = Customer.create!(company: "株式会社エスエーピー", business: "情報通信,SAP")
    partial = Customer.create!(company: "株式会社札幌", business: "SAPPORO")

    sap_ids = Customer.with_business("SAP").pluck(:id)
    telecom_ids = Customer.with_business("情報通信").pluck(:id)

    assert_includes sap_ids, listed.id
    assert_includes telecom_ids, listed.id
    refute_includes sap_ids, partial.id
    refute_includes telecom_ids, partial.id
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
