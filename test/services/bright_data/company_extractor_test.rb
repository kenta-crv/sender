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
    assert_equal "株式会社ライフプラテック | 会社概要", companies.first[:title]
    assert_equal "https://www.lifeplatech.co.jp/company/", companies.first[:url]
  end

  test "extract keeps company name that appears after title separators" do
    serp_result = {
      "organic_results" => [
        {
          "title" => "会社概要｜企業情報｜佐藤食品株式会社",
          "link" => "https://www.satou-shokuhin.co.jp/company/outline/"
        }
      ]
    }

    company = BrightData::CompanyExtractor.extract(serp_result).first

    assert_equal "佐藤食品株式会社", company[:company]
    assert_equal "会社概要｜企業情報｜佐藤食品株式会社", company[:title]
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

  test "uses query company when organic title is generic" do
    serp_result = {
      "organic_results" => [
        { "title" => "会社概要", "link" => "https://sign3.net/about/" }
      ]
    }

    companies = BrightData::CompanyExtractor.extract(
      serp_result,
      query: "Sign合同会社 大阪府茨木市 会社概要"
    )

    assert_equal 1, companies.size
    assert_equal "Sign合同会社", companies.first[:company]
    assert_equal "https://sign3.net/about/", companies.first[:url]
  end

  test "skips generic organic titles when query company is unavailable" do
    serp_result = {
      "organic_results" => [
        { "title" => "会社概要", "link" => "https://example.com/about/" }
      ]
    }

    assert_empty BrightData::CompanyExtractor.extract(serp_result)
  end

  test "uses only the first generic title fallback for a query" do
    serp_result = {
      "organic_results" => [
        { "title" => "会社概要", "link" => "https://www.dpl1.net/blank-1" },
        { "title" => "会社概要", "link" => "https://www.lifeplatech.co.jp/aboutus/" }
      ]
    }

    companies = BrightData::CompanyExtractor.extract(
      serp_result,
      query: "株式会社第一プラテック 大阪府茨木市 会社概要"
    )

    assert_equal ["https://www.dpl1.net/blank-1"], companies.map { |company| company[:url] }
  end

  test "does not match short roman company names by prefix" do
    serp_result = {
      "organic_results" => [
        { "title" => "株式会社CSCサービス", "link" => "https://csc.service.co.jp/" },
        { "title" => "株式会社CSC", "link" => "https://csc-kk.com/aboutus/" }
      ]
    }

    companies = BrightData::CompanyExtractor.extract(
      serp_result,
      query: "株式会社CSC 大阪府堺市 会社概要"
    )

    assert_equal ["株式会社CSC"], companies.map { |company| company[:company] }
    assert_equal ["https://csc-kk.com/aboutus/"], companies.map { |company| company[:url] }
  end

  test "uses non-corporate query name only when the title contains it" do
    serp_result = {
      "organic_results" => [
        { "title" => "会社概要", "link" => "https://yukiline.com/information" },
        { "title" => "軽貨物配送サービス | PALZカーゴ", "link" => "https://palzcargo.hp.peraichi.com/top/" }
      ]
    }

    companies = BrightData::CompanyExtractor.extract(
      serp_result,
      query: "PALZカーゴ 大阪府摂津市 会社概要"
    )

    assert_equal ["PALZカーゴ"], companies.map { |company| company[:company] }
    assert_equal ["https://palzcargo.hp.peraichi.com/top/"], companies.map { |company| company[:url] }
  end

  test "sanitizes prefixed corporate titles" do
    serp_result = {
      "organic_results" => [
        { "title" => "自動車部品販売の株式会社ムラセ", "link" => "http://www.ap-murase.co.jp/company/index.html" }
      ]
    }

    companies = BrightData::CompanyExtractor.extract(
      serp_result,
      query: "株式会社ムラセ 大阪府寝屋川市 会社概要"
    )

    assert_equal ["株式会社ムラセ"], companies.map { |company| company[:company] }
  end
end
