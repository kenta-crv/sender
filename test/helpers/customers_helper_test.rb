require "test_helper"

class CustomersHelperTest < ActionView::TestCase
  test "detailed_address? requires prefecture, municipality, and street detail" do
    assert detailed_address?("大阪府貝塚市二色中町4-1")
    assert detailed_address?("東京都港区芝5-27-3 MBC・Aー9")

    refute detailed_address?("大阪府")
    refute detailed_address?("大阪府 茨木市")
    refute detailed_address?("大阪府 大阪市 ユニバーサルシティ駅 車10分")
    refute detailed_address?("大阪府 大東市 住道駅")
    refute detailed_address?("")
    refute detailed_address?(nil)
  end

  test "address_quality_icon distinguishes missing, partial, and detailed addresses" do
    assert_includes address_quality_icon(nil), "住所未取得"
    assert_includes address_quality_icon("大阪府 茨木市"), "都道府県・市区町村止まり"
    assert_includes address_quality_icon("大阪府 大阪市 ユニバーサルシティ駅 車10分"), "駅/アクセス表記"
    assert_includes address_quality_icon("大阪府貝塚市二色中町4-1"), "番地相当まで取得済み"
  end

  test "url_quality_icon distinguishes official urls from excluded database urls" do
    assert_includes url_quality_icon(nil), "公式URL未取得"
    assert_includes url_quality_icon("https://www.lifeplatech.co.jp/"), "公式URL取得済み"
    assert_includes url_quality_icon("https://cnavi.g-search.or.jp/detail/9120901047557.html"), "公式URL扱いしない"
  end

  test "display_datetime uses Japan time" do
    time = Time.utc(2026, 5, 13, 7, 34)
    assert_equal "05/13 16:34", display_datetime(time)
  end
end
