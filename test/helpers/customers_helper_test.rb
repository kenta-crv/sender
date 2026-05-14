require "test_helper"

class CustomersHelperTest < ActionView::TestCase
  test "detailed_address? requires prefecture, municipality, and street detail" do
    assert detailed_address?("大阪府貝塚市二色中町4-1")
    assert detailed_address?("東京都港区芝5-27-3 MBC・Aー9")

    refute detailed_address?("大阪府")
    refute detailed_address?("大阪府 茨木市")
    refute detailed_address?("大阪府 大阪市 ユニバーサルシティ駅 車10分")
    refute detailed_address?("大阪府 大東市 住道駅")
    refute detailed_address?("神奈川県相模原市南区若松 荷物積み込み場 神奈川県相模原市南区若松 時間 8時から20時")
    refute detailed_address?("大阪府大阪市中央区城見1-2-27　クリスタルタワー 3F 役員 代表取締役会長")
    refute detailed_address?("神奈川県横浜市港北区新羽町673-1法人営業部〒223-0057神奈川県横浜市港北区新羽町673-1")
    refute detailed_address?("")
    refute detailed_address?(nil)
  end

  test "address_quality_icon distinguishes missing, partial, and detailed addresses" do
    assert_includes address_quality_icon(nil), "住所未取得"
    assert_includes address_quality_icon("大阪府 茨木市"), "都道府県・市区町村止まり"
    assert_includes address_quality_icon("大阪府 大阪市 ユニバーサルシティ駅 車10分"), "駅/アクセス表記"
    assert_includes address_quality_icon("大阪府貝塚市二色中町4-1"), "番地相当まで取得済み"
  end

  test "display_address hides partial or access-style addresses" do
    assert_nil display_address(nil)
    assert_nil display_address("大阪府 大阪市 西淀川区")
    assert_nil display_address("大阪府 大東市 住道駅")
    assert_nil display_address("大阪府 大阪市 ユニバーサルシティ駅 車10分")

    assert_equal "大阪府貝塚市二色中町4-1", display_address("大阪府貝塚市二色中町4-1")
    assert_equal "愛知県名古屋市西区名駅2丁目34-17 セントラル名古屋",
                 display_address("愛知県名古屋市西区名駅2丁目34-17 セントラル名古屋")
    assert_equal "長崎県大村市東三城町6-1 大村バスターミナルビル　3F",
                 display_address("長崎県大村市東三城町6-1 大村バスターミナルビル　3F")
  end

  test "url_quality_icon distinguishes official urls from excluded database urls" do
    assert_includes url_quality_icon(nil), "公式URL未取得"
    assert_includes url_quality_icon("https://www.lifeplatech.co.jp/"), "公式URL取得済み"
    assert_includes url_quality_icon("https://cnavi.g-search.or.jp/detail/9120901047557.html"), "公式URL扱いしない"
  end

  test "tel_quality_icon marks external directory evidence as warning" do
    assert_includes tel_quality_icon(Customer.new(tel: "03-0000-0000")), "公式または公式サイト由来"
    assert_includes tel_quality_icon(Customer.new(tel: nil, contact_url: "https://daikonavi.com/contact.php")), "外部サイト上に電話番号情報あり"
    assert_includes tel_quality_icon(Customer.new(tel: nil, contact_url: nil)), "電話番号未取得"
  end

  test "display_company_name hides job department noise" do
    customer = Customer.new(company: "ドライバーズサポート株式会社宅配課")
    assert_equal "ドライバーズサポート株式会社", display_company_name(customer)

    clean = Customer.new(company: "ままここびより／株式会社ハーベスト")
    assert_equal "ままここびより／株式会社ハーベスト", display_company_name(clean)
  end

  test "display_datetime uses Japan time" do
    time = Time.utc(2026, 5, 13, 7, 34)
    assert_equal "05/13 16:34", display_datetime(time)
  end
end
