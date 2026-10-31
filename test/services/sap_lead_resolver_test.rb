require "test_helper"

class SapLeadResolverTest < ActiveSupport::TestCase
  class FakeApi
    def initialize(search:, detail:)
      @search = search
      @detail = detail
    end

    def search_by_name(_name)
      @search
    end

    def basic_info(_number)
      @detail
    end
  end

  test "tidy removes a trailing branch and a truncated last word" do
    assert_equal "株式会社テスト", SapLead::CompanyName.tidy("株式会社テスト 東京オフィス")
    assert_equal "株式会社テスト", SapLead::CompanyName.tidy("株式会社テスト ソリューション...")
  end

  test "resolves one open exact match and drops a blocked homepage" do
    posting = JobPosting.create!(
      source: "kyujinbox",
      company_raw: "株式会社テスト 東京支店",
      company_clean: "テスト",
      title: "SAPコンサルタント",
      area: "東京都",
      job_key: "jbn:resolve1",
      status: "new",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
    api = FakeApi.new(
      search: [
        { "corporate_number" => "111", "name" => "株式会社テスト", "status" => "" },
        { "corporate_number" => "222", "name" => "株式会社テスト商事", "status" => "" },
        { "corporate_number" => "333", "name" => "株式会社テスト", "status" => "閉鎖" }
      ],
      detail: {
        "corporate_number" => "111",
        "name" => "株式会社テスト",
        "location" => "東京都千代田区1-1",
        "company_url" => "https://xn--pckua2a7gp15o89zb.com/company",
        "close_date" => ""
      }
    )

    stats = SapLead::Resolver.new(client: api).run

    posting.reload
    assert_equal 1, stats[:resolved]
    assert_equal "resolved", posting.status
    assert_equal "111", posting.corporate_number
    assert_equal "株式会社テスト", posting.official_name
    assert_equal "東京都千代田区1-1", posting.headquarters_address
    assert_nil posting.official_url
  end

  test "skips when no open corporation has the same name" do
    posting = JobPosting.create!(
      source: "kyujinbox",
      company_raw: "株式会社なし",
      company_clean: "なし",
      job_key: "jbn:resolve-none",
      status: "new",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )

    SapLead::Resolver.new(client: FakeApi.new(search: [], detail: nil)).run

    assert_equal "skipped", posting.reload.status
    assert_equal "法人番号なし", posting.skip_reason
  end

  test "skips when several open corporations share the name" do
    posting = JobPosting.create!(
      source: "kyujinbox",
      company_raw: "株式会社重複",
      company_clean: "重複",
      job_key: "jbn:resolve-many",
      status: "new",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
    api = FakeApi.new(
      search: [
        { "corporate_number" => "1", "name" => "株式会社重複", "status" => "" },
        { "corporate_number" => "2", "name" => "株式会社重複", "status" => "" }
      ],
      detail: nil
    )

    SapLead::Resolver.new(client: api).run

    assert_equal "skipped", posting.reload.status
    assert_equal "同名複数", posting.skip_reason
  end

  test "missing api token stops the job and leaves the posting new" do
    posting = JobPosting.create!(
      source: "kyujinbox",
      company_raw: "株式会社テスト",
      company_clean: "テスト",
      job_key: "jbn:resolve-token",
      status: "new",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
    Gbizinfo::Client
    api = Object.new
    def api.search_by_name(_name)
      raise Gbizinfo::MissingToken, "GBIZINFO_API_TOKEN が未設定です"
    end

    assert_raises(Gbizinfo::MissingToken) do
      SapLead::Resolver.new(client: api).run
    end
    assert_equal "new", posting.reload.status
  end
end
