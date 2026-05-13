require "test_helper"

class CustomersHelperTest < ActionView::TestCase
  test "detailed_address? requires prefecture, municipality, and street detail" do
    assert detailed_address?("大阪府貝塚市二色中町4-1")
    assert detailed_address?("東京都港区芝5-27-3 MBC・Aー9")

    refute detailed_address?("大阪府")
    refute detailed_address?("大阪府 茨木市")
    refute detailed_address?("")
    refute detailed_address?(nil)
  end

  test "address_quality_icon distinguishes missing, partial, and detailed addresses" do
    assert_includes address_quality_icon(nil), "住所未取得"
    assert_includes address_quality_icon("大阪府 茨木市"), "都道府県・市区町村止まり"
    assert_includes address_quality_icon("大阪府貝塚市二色中町4-1"), "番地相当まで取得済み"
  end
end
