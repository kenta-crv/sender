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

  test "usable url drops pdfs, keeps group pages, and folds the rest to the site root" do
    resolver = SapLead::Resolver.new(client: FakeApi.new(search: [], detail: nil))

    assert_nil resolver.send(:usable_url, "https://example.com/ir/report.pdf")
    assert_nil resolver.send(:usable_url, "https://example.com/files/report.PDF")
    assert_equal "https://parent.example/group/child/about?x=1", resolver.send(:usable_url, "https://parent.example/group/child/about?x=1")
    assert_equal "https://www.pwc.com/jp/ja/", resolver.send(:usable_url, "https://www.pwc.com/jp/ja/about/services")
    assert_equal "https://www.pwc.com/jp/ja/", resolver.send(:usable_url, "https://www.pwc.com/jp/ja")
    assert_equal "http://example.com/ja_jp/", resolver.send(:usable_url, "http://example.com/ja_jp/news")
    assert_equal "https://example.com/global/ja/", resolver.send(:usable_url, "https://example.com/global/ja/company")
    assert_equal "https://example.com/jp/", resolver.send(:usable_url, "https://example.com/jp/company")
    assert_equal "https://example.com/ja/", resolver.send(:usable_url, "https://example.com/ja/company")
    assert_equal "http://www.example.com/", resolver.send(:usable_url, "http://www.example.com/about/company")
  end

  test "usable url keeps the original http scheme" do
    resolver = SapLead::Resolver.new(client: FakeApi.new(search: [], detail: nil))

    assert_equal "http://example.com/jp/", resolver.send(:usable_url, "http://example.com/jp/company")
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

  test "a 404 from name search skips the posting as no corporate number" do
    posting = new_posting("jbn:resolve-404-search", "株式会社なし")

    SapLead::Resolver.new(client: sequence_client(["404"])).run

    assert_equal "skipped", posting.reload.status
    assert_equal "法人番号なし", posting.skip_reason
  end

  test "a 404 from basic info skips the posting as no corporate number" do
    posting = new_posting("jbn:resolve-404-detail", "株式会社テスト")
    body = {
      "hojin-infos" => [
        { "corporate_number" => "111", "name" => "株式会社テスト", "status" => "" }
      ]
    }.to_json

    SapLead::Resolver.new(client: sequence_client(["200", "404"], body)).run

    assert_equal "skipped", posting.reload.status
    assert_equal "法人番号なし", posting.skip_reason
  end

  private

  def new_posting(job_key, company)
    JobPosting.create!(
      source: "kyujinbox",
      company_raw: company,
      company_clean: company,
      job_key: job_key,
      status: "new",
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
  end

  def sequence_client(codes, success_body = "{}")
    http = Class.new do
      def initialize(codes, success_body)
        @codes = codes.dup
        @success_body = success_body
      end

      def start(*)
        code = @codes.shift || "404"
        success_body = @success_body
        response = Object.new
        response.define_singleton_method(:code) { code }
        response.define_singleton_method(:body) { code == "200" ? success_body : "" }
        yield Object.new.tap { |connection| connection.define_singleton_method(:request) { |_req| response } }
      end
    end.new(codes, success_body)
    Gbizinfo::Client.new(token: "test-token", http: http)
  end
end
