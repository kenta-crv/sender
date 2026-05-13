require "test_helper"

class BrightData::UrlPolicyTest < ActiveSupport::TestCase
  test "official_url? allows company home pages" do
    assert BrightData::UrlPolicy.official_url?("https://www.lifeplatech.co.jp/")
  end

  test "official_url? rejects job and directory domains" do
    rejected = [
      "https://doda.jp/DodaFront/View/Company/j_id__10146794280/",
      "https://syukatsu-kaigi.jp/companies/30039/screening_experiences",
      "https://toukibo.ai-con.lawyer/search-service/result/8140001044561",
      "https://www.buffett-code.com/company/6a7n75947k/",
      "https://houjin.jp/c/6120901041117",
      "https://salesnow.jp/db/companies/jcb8j5xxh0r49u19e",
      "https://job.logiquest.co.jp/jobfind-smartphone/job/4995",
      "https://gaten.info/job/16924",
      "https://jp.ldigi.com.tw/detail.php?ban_no=9120101059122"
    ]

    rejected.each do |url|
      assert BrightData::UrlPolicy.excluded_url?(url), "#{url} should be excluded"
    end
  end

  test "official_url? rejects noisy titles and paths" do
    assert BrightData::UrlPolicy.excluded_url?("https://example.com/company", title: "株式会社ABCの転職・企業概要")
    assert BrightData::UrlPolicy.excluded_url?("https://example.com/recruit/", title: "株式会社ABC 採用情報")
  end

  test "normalize_company_name removes SERP title noise" do
    assert_equal "株式会社第一プラテック", BrightData::UrlPolicy.normalize_company_name("株式会社第一プラテックの転職・企業概要")
    assert_equal "株式会社第一プラテック", BrightData::UrlPolicy.normalize_company_name("株式会社第一プラテック(法人番号")
    assert_equal "株式会社ZOOOM TRANSPORT", BrightData::UrlPolicy.normalize_company_name("株式会社ZOOOM TRANSPORT(大阪府大東市)の企業詳細")
    assert_equal "株式会社STAG", BrightData::UrlPolicy.normalize_company_name("株式会社STAGの会社概要【2026年最新】")
    assert_equal "株式会社ライフプラテック", BrightData::UrlPolicy.normalize_company_name("株式会社ライフプラテック")
  end
end
