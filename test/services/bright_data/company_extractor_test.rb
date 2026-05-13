require "test_helper"

class BrightData::CompanyExtractorTest < ActiveSupport::TestCase
  test "extract skips job and directory organic results" do
    serp_result = {
      "organic_results" => [
        {
          "title" => "株式会社第一プラテックの転職・企業概要",
          "link" => "https://doda.jp/DodaFront/View/Company/j_id__10146794280/"
        },
        {
          "title" => "株式会社第一プラテック(法人番号",
          "link" => "https://toukibo.ai-con.lawyer/search-service/result/8140001044561"
        },
        {
          "title" => "株式会社STAGの会社概要【2026年最新】",
          "link" => "https://salesnow.jp/db/companies/jcb8j5xxh0r49u19e"
        },
        {
          "title" => "株式会社ライフプラテック | 会社概要",
          "link" => "https://www.lifeplatech.co.jp/company/"
        }
      ]
    }

    companies = BrightData::CompanyExtractor.extract(serp_result, query: "株式会社ライフプラテック 会社概要")

    assert_equal 1, companies.size
    assert_equal "株式会社ライフプラテック", companies.first[:company]
    assert_equal "https://www.lifeplatech.co.jp/company/", companies.first[:url]
  end

  test "extract keeps local data but does not keep excluded urls" do
    serp_result = {
      "local_results" => [
        {
          "title" => "株式会社第一プラテック",
          "phone" => "06-0000-0000",
          "address" => "大阪府大阪市北区1-1",
          "website" => "https://houjin.jp/c/8140001044561"
        }
      ]
    }

    company = BrightData::CompanyExtractor.extract(serp_result).first

    assert_equal "株式会社第一プラテック", company[:company]
    assert_equal "06-0000-0000", company[:tel]
    assert_nil company[:url]
  end
end
