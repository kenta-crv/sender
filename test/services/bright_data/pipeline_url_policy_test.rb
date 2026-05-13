require "test_helper"

class BrightData::PipelineUrlPolicyTest < ActiveSupport::TestCase
  test "build_web_updates adopts only matched official urls" do
    customer = Customer.create!(company: "株式会社ライフプラテック")

    official = {
      company: "株式会社ライフプラテック",
      url: "https://www.lifeplatech.co.jp/company/",
      source: "organic"
    }
    updates = BrightData::Pipeline.send(:build_web_updates, customer, official, { matched: true })
    assert_equal "https://www.lifeplatech.co.jp/company/", updates[:url]

    job_site = {
      company: "株式会社ライフプラテックの転職・企業概要",
      url: "https://doda.jp/DodaFront/View/Company/j_id__10009818961/",
      source: "organic"
    }
    updates = BrightData::Pipeline.send(:build_web_updates, customer, job_site, { matched: true })
    refute_includes updates.keys, :url

    unverified = {
      company: "株式会社ライフプラテック",
      url: "https://www.lifeplatech.co.jp/",
      source: "organic"
    }
    updates = BrightData::Pipeline.send(:build_web_updates, customer, unverified, { matched: nil, tel: "06-0000-0000" })
    refute_includes updates.keys, :url
  end

  test "build_serp_updates keeps direct tel and address but rejects directory urls" do
    customer = Customer.create!(company: "株式会社第一プラテック", address: "大阪府")
    company = {
      company: "株式会社第一プラテック",
      url: "https://houjin.jp/c/8140001044561",
      tel: "06-0000-0000",
      address: "大阪府大阪市北区1-1",
      source: "knowledge_graph"
    }

    updates = BrightData::Pipeline.send(:build_serp_updates, customer, company)

    refute_includes updates.keys, :url
    assert_equal "06-0000-0000", updates[:tel]
    assert_equal "大阪府大阪市北区1-1", updates[:address]
  end

  test "execute_from_db selects most recently reset targets first" do
    Customer.create!(company: "Old Target", address: "Osaka", updated_at: 2.days.ago)
    Customer.create!(company: "New Reset Target", address: "Osaka", updated_at: 1.minute.ago)

    captured_queries = []
    fake_client = Object.new
    fake_client.define_singleton_method(:batch_search) do |queries, delay_between: 1|
      captured_queries.replace(queries)
      queries.map { |query| { "query" => query, "result" => {}, "timestamp" => Time.current.iso8601 } }
    end

    with_singleton_method(BrightData::SerpClient, :new, -> { fake_client }) do
      with_singleton_method(BrightData::ResultStore, :save_batch, ->(_batch) {}) do
        BrightData::Pipeline.execute_from_db(limit: 1, dry_run: true)
      end
    end

    assert_equal 1, captured_queries.size
    assert_match(/\ANew Reset Target/, captured_queries.first)
  end

  private

  def with_singleton_method(klass, method_name, replacement)
    original = klass.method(method_name)
    klass.define_singleton_method(method_name, &replacement)
    yield
  ensure
    klass.define_singleton_method(method_name) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end
end
