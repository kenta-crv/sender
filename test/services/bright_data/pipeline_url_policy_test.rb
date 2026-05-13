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
end
