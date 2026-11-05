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

  test "appends SAP to a client owned company with the same name" do
    client = Client.create!(email: "sap-owned-#{SecureRandom.hex(4)}@example.com", password: "password123")
    owned = Customer.create!(
      company: "株式会社所有のみ",
      business: "製造",
      url: "https://owned-only.example",
      tel: "0311112222",
      contact_url: "https://owned-only.example/contact",
      client: client
    )
    posting = resolved_posting("jbn:reg-owned-only", official_url: "https://owned-only.example", company: "株式会社所有のみ")
    assert_equal owned.id, SapLead::DuplicateFinder.new.find(company: "株式会社所有のみ", tel: "0311112222", url: "https://owned-only.example").id

    stats = SapLead::Registrar.new.run

    owned.reload
    assert_equal 0, stats[:created]
    assert_equal 1, stats[:appended]
    assert_equal "製造,SAP", owned.business
    assert_equal "https://owned-only.example/contact", owned.contact_url
    assert_nil Customer.find_by(company: "株式会社所有のみ", client_id: nil)
    assert_equal owned.id, posting.reload.customer_id
  end

  test "does not match a company when only the legal entity position differs" do
    security = Customer.create!(company: "アシスト株式会社", business: "警備")
    posting = resolved_posting("jbn:reg-front-stock", official_url: "https://front-assist.example", company: "株式会社アシスト")

    assert_nil SapLead::DuplicateFinder.new.find(company: "株式会社アシスト")
    stats = SapLead::Registrar.new.run

    security.reload
    created = Customer.find_by!(company: "株式会社アシスト")
    assert_equal 1, stats[:created]
    assert_equal "警備", security.business
    assert_equal created.id, posting.reload.customer_id
    refute_equal security.id, created.id
  end

  test "links a skipped posting when exactly one customer has the same full name" do
    existing = Customer.create!(
      company: "株式会社一意",
      business: "製造",
      contact_url: "https://keep.example/contact",
      url: "https://keep.example"
    )
    duplicate_name = skipped_posting("jbn:skip-unique", "株式会社　一意", "同名複数")
    missing_number = skipped_posting("jbn:skip-missing", "株式会社番号なし", "法人番号なし")
    Customer.create!(company: "株式会社番号なし", business: "情報通信", contact_url: "https://number.example/contact")

    stats = SapLead::Registrar.new.run

    existing.reload
    number_customer = Customer.find_by!(company: "株式会社番号なし")
    assert_equal 2, stats[:appended]
    assert_equal 0, stats[:created]
    assert_equal "製造,SAP", existing.business
    assert_equal "https://keep.example/contact", existing.contact_url
    assert_equal existing.id, duplicate_name.reload.customer_id
    assert_equal "registered", duplicate_name.status
    assert_equal "appended", duplicate_name.registration_kind
    assert_equal "情報通信,SAP", number_customer.business
    assert_equal "https://number.example/contact", number_customer.contact_url
    assert_equal number_customer.id, missing_number.reload.customer_id
  end

  test "does not link a skipped posting when the full name matches two customers or only the legal entity position differs" do
    Customer.create!(company: "株式会社重複", business: "製造", contact_url: "https://dup-a.example/contact")
    Customer.create!(company: "株式会社　重複", business: "製造", contact_url: "https://dup-b.example/contact")
    security = Customer.create!(company: "アシスト株式会社", business: "警備", contact_url: "https://security.example/contact")
    ambiguous = skipped_posting("jbn:skip-ambiguous", "株式会社重複", "同名複数")
    different_position = skipped_posting("jbn:skip-front-stock", "株式会社アシスト", "法人番号なし")

    stats = SapLead::Registrar.new.run

    assert_equal 0, stats[:appended]
    assert_equal 0, stats[:created]
    assert_nil ambiguous.reload.customer_id
    assert_equal "skipped", ambiguous.status
    assert_nil different_position.reload.customer_id
    assert_equal "skipped", different_position.status
    assert_equal "警備", security.reload.business
    assert_equal "https://security.example/contact", security.contact_url
  end

  test "keeps a blocked contact url and fills a blank company url from gBiz" do
    existing = Customer.create!(
      company: "株式会社ハロー",
      business: "製造",
      url: nil,
      contact_url: "https://jinzai.hellowork.mhlw.go.jp/jobs/1"
    )
    posting = resolved_posting(
      "jbn:reg-blocked-contact",
      official_url: "https://hello-company.example",
      company: "株式会社ハロー"
    )

    stats = SapLead::Registrar.new.run

    existing.reload
    assert_equal 1, stats[:appended]
    assert_equal "製造,SAP", existing.business
    assert_equal "https://jinzai.hellowork.mhlw.go.jp/jobs/1", existing.contact_url
    assert_equal "https://hello-company.example", existing.url
    assert_equal existing.id, posting.reload.customer_id
  end

  test "stores the company name in NFKC" do
    posting = resolved_posting(
      "jbn:reg-nfkc",
      official_url: "https://digi.example",
      company: "ＤＩＧＩ　ＧＲＯＷＴＨ株式会社"
    )

    SapLead::Registrar.new.run

    customer = Customer.find_by!(company: "DIGI GROWTH株式会社", client_id: nil)
    assert_equal "DIGI GROWTH株式会社", JSON.parse(customer.template_vars)["company"]
    assert_equal customer.id, posting.reload.customer_id
  end

  test "area is the prefecture and municipality from the headquarters" do
    assert_equal "東京都千代田区", SapLead::HeadquartersArea.extract("東京都千代田区霞が関2-1-3")
    assert_equal "大阪府大阪市北区", SapLead::HeadquartersArea.extract("大阪府大阪市北区中之島3丁目")
    assert_equal "北海道札幌市中央区", SapLead::HeadquartersArea.extract("北海道札幌市中央区北1条")
    assert_equal "東京都町田市", SapLead::HeadquartersArea.extract("東京都町田市森野")
    assert_equal "千葉県船橋市", SapLead::HeadquartersArea.extract("千葉県船橋市湊町")
    assert_equal "沖縄県那覇市", SapLead::HeadquartersArea.extract("沖縄県那覇市旭町1-9カフーナ旭橋B街区")
    assert_equal "", SapLead::HeadquartersArea.extract("千代田区")
    assert_equal "", SapLead::HeadquartersArea.extract("")

    posting = resolved_posting(
      "jbn:reg-area",
      official_url: "https://area.example",
      headquarters_address: "神奈川県横浜市西区みなとみらい1"
    )
    SapLead::Registrar.new.run

    customer = Customer.find_by!(company: "株式会社テスト", url: "https://area.example")
    assert_equal "神奈川県横浜市西区", JSON.parse(customer.template_vars)["area"]
    assert_equal customer.id, posting.reload.customer_id
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

  def skipped_posting(job_key, company, skip_reason)
    JobPosting.create!(
      source: "kyujinbox",
      company_raw: company,
      company_clean: company,
      title: "SAPコンサルタント",
      job_key: job_key,
      status: "skipped",
      skip_reason: skip_reason,
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
  end

  def resolved_posting(job_key, official_url:, company: "株式会社テスト", headquarters_address: "東京都千代田区1-1")
    JobPosting.create!(
      source: "kyujinbox",
      company_raw: company,
      company_clean: company,
      title: "SAPコンサルタント",
      area: "東京都",
      official_name: company,
      headquarters_address: headquarters_address,
      official_url: official_url,
      job_key: job_key,
      status: "resolved",
      corporate_number: "1234567890123",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
  end
end
