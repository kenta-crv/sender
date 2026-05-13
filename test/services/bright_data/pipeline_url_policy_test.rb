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

  test "build_url_fallback_update keeps clear official SERP urls when html verification cannot finish" do
    customer = Customer.create!(company: "佐藤食品株式会社")
    company = {
      company: "佐藤食品株式会社",
      title: "会社概要｜企業情報｜佐藤食品株式会社",
      url: "https://www.satou-shokuhin.co.jp/company/outline/",
      source: "organic"
    }

    updates = BrightData::Pipeline.send(:build_url_fallback_update, customer, company)

    assert_equal "https://www.satou-shokuhin.co.jp/company/outline/", updates[:url]
  end

  test "build_url_fallback_update rejects unclear or excluded SERP urls" do
    customer = Customer.create!(company: "ジャパンパレック株式会社 福岡 久山センター")

    generic = {
      company: "会社概要",
      title: "会社概要",
      url: "https://hoko.co.jp/corporate/outline",
      source: "organic"
    }
    job_site = {
      company: "ジャパンパレック株式会社",
      title: "ジャパンパレック株式会社の会社概要",
      url: "https://tenshoku.mynavi.jp/company/416106/",
      source: "organic"
    }

    assert_empty BrightData::Pipeline.send(:build_url_fallback_update, customer, generic)
    assert_empty BrightData::Pipeline.send(:build_url_fallback_update, customer, job_site)
  end

  test "build_url_fallback_update does not reject official titles containing expert" do
    customer = Customer.create!(company: "株式会社シーエル")
    company = {
      company: "株式会社シーエル",
      title: "株式会社シーエル | 3PLのエキスパート企業",
      url: "https://www.cl-gp.co.jp/",
      source: "organic"
    }

    updates = BrightData::Pipeline.send(:build_url_fallback_update, customer, company)

    assert_equal "https://www.cl-gp.co.jp/", updates[:url]
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

  test "execute_from_db skips legacy contact detector in db mode" do
    Customer.create!(company: "Contact Skip Target", address: "Osaka")

    fake_client = Object.new
    fake_client.define_singleton_method(:batch_search) do |queries, delay_between: 1|
      queries.map { |query| { "query" => query, "result" => {}, "timestamp" => Time.current.iso8601 } }
    end

    with_singleton_method(BrightData::SerpClient, :new, -> { fake_client }) do
      with_singleton_method(BrightData::ResultStore, :save_batch, ->(_batch) {}) do
        with_singleton_method(BrightData::ContactUrlEnricher, :enrich, ->(_companies) { flunk "DB mode should not run legacy ContactUrlEnricher" }) do
          BrightData::Pipeline.execute_from_db(limit: 1, detect_contact: true, dry_run: true)
        end
      end
    end
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
