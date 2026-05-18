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
    assert_equal "https://www.lifeplatech.co.jp/", updates[:url]
    assert_equal "06-0000-0000", updates[:tel]
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

  test "build_url_fallback_update keeps generic official urls when web verification matched" do
    customer = Customer.create!(company: "株式会社UDエクスプレス")
    company = {
      company: "横浜周辺で定期便・スポット便なら",
      title: "横浜周辺で定期便・スポット便なら",
      url: "https://ud-group.site/about/",
      source: "organic"
    }
    web_data = { matched: true, source_url: "https://ud-group.site/about/" }

    updates = BrightData::Pipeline.send(:build_url_fallback_update, customer, company, web_data: web_data)

    assert_equal "https://ud-group.site/about/", updates[:url]
  end

  test "build_url_fallback_update keeps matched headquarters even when current address is a work location" do
    customer = Customer.create!(company: "合同会社アイズ", address: "神奈川県 相模原市 中央区")
    company = {
      company: "合同会社アイズ",
      title: "会社概要 - 合同会社アイズ",
      url: "https://www.aizu-hp.com/company",
      source: "organic"
    }
    web_data = {
      matched: true,
      source_url: "https://www.aizu-hp.com/company",
      address: "東京都八王子市上柚木3-16-4-210"
    }

    updates = BrightData::Pipeline.send(:build_url_fallback_update, customer, company, web_data: web_data)

    assert_equal "https://www.aizu-hp.com/company", updates[:url]
  end

  test "build_url_fallback_update does not store contact pages as company url" do
    customer = Customer.create!(company: "トーヨークリエイツ株式会社")
    company = {
      company: "トーヨークリエイツ株式会社",
      title: "会社概要・お問い合わせ",
      url: "https://ty-create.co.jp/contact",
      source: "organic"
    }

    assert_empty BrightData::Pipeline.send(:build_url_fallback_update, customer, company)
  end

  test "contact-like URL detection does not reject information pages" do
    customer = Customer.create!(company: "株式会社雅架設")
    company = {
      company: "株式会社雅架設",
      title: "会社概要",
      url: "https://miyabi-kasetsu.yokohama/information",
      source: "organic"
    }

    updates = BrightData::Pipeline.send(
      :build_web_updates,
      customer,
      company,
      {
        matched: true,
        source_url: "https://miyabi-kasetsu.yokohama/information",
        tel: "080-9987-1380"
      }
    )

    assert_equal "https://miyabi-kasetsu.yokohama/information", updates[:url]
    assert_equal "080-9987-1380", updates[:tel]
    assert BrightData::Pipeline.send(:contact_like_url?, "https://example.com/contact/form")
    refute BrightData::Pipeline.send(:contact_like_url?, "https://example.com/information")
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

  test "build_web_updates replaces stale relative contact urls" do
    customer = Customer.create!(
      company: "Relative Contact Target",
      contact_url: "/contact"
    )
    company = {
      company: "Relative Contact Target",
      url: "https://example.com/company/",
      source: "organic"
    }

    updates = BrightData::Pipeline.send(
      :build_web_updates,
      customer,
      company,
      { matched: true, contact_url: "https://example.com/contact/" }
    )

    assert_equal "https://example.com/contact/", updates[:contact_url]
  end

  test "build_web_updates corrects phone formatting when digits are unchanged" do
    customer = Customer.create!(
      company: "Toll Free Target",
      tel: "080-0919-9966"
    )
    company = {
      company: "Toll Free Target",
      url: "https://example.com/company/",
      source: "organic"
    }

    updates = BrightData::Pipeline.send(
      :build_web_updates,
      customer,
      company,
      { matched: true, tel: "0800-919-9966" }
    )

    assert_equal "0800-919-9966", updates[:tel]
  end

  test "build_web_updates stores profile source url instead of contact landing page" do
    customer = Customer.create!(company: "トーヨークリエイツ株式会社", url: "https://ty-create.co.jp/contact")
    company = {
      company: "トーヨークリエイツ株式会社",
      url: "https://ty-create.co.jp/contact",
      source: "organic"
    }

    updates = BrightData::Pipeline.send(
      :build_web_updates,
      customer,
      company,
      {
        matched: true,
        source_url: "https://ty-create.co.jp/company.html",
        contact_url: "https://ty-create.co.jp/contact.html"
      }
    )

    assert_equal "https://ty-create.co.jp/company.html", updates[:url]
    assert_equal "https://ty-create.co.jp/contact.html", updates[:contact_url]
  end

  test "build_web_updates replaces previously stored directory urls" do
    customer = Customer.create!(
      company: "G・Mライン株式会社",
      url: "https://www.job-j.net/company/detail/3233103/",
      tel: "049-270-6284",
      address: "埼玉県入間郡毛呂山町目白台1-20-8"
    )
    company = {
      company: "G・Mライン株式会社",
      title: "会社概要",
      url: "https://gm-line-kk.net/about/",
      source: "organic"
    }

    updates = BrightData::Pipeline.send(
      :build_web_updates,
      customer,
      company,
      {
        matched: true,
        source_url: "https://gm-line-kk.net/about/",
        tel: "049-270-6284",
        address: "埼玉県入間郡毛呂山町目白台1-20-8",
        contact_url: "https://gm-line-kk.net/contact/"
      }
    )

    assert_equal "https://gm-line-kk.net/about/", updates[:url]
    assert_equal "https://gm-line-kk.net/contact/", updates[:contact_url]
  end

  test "build_web_updates clears excluded existing contact url when no valid replacement exists" do
    customer = Customer.create!(
      company: "株式会社ホートー",
      url: "http://www.hoto.co.jp/",
      contact_url: "https://hoto-recruit.com/contact/"
    )
    company = {
      company: "株式会社ホートー",
      title: "株式会社ホートー",
      url: "http://www.hoto.co.jp/",
      source: "organic"
    }

    updates = BrightData::Pipeline.send(
      :build_web_updates,
      customer,
      company,
      { matched: true, source_url: "http://www.hoto.co.jp/", tel: "049-245-9161" }
    )

    assert_includes updates.keys, :contact_url
    assert_nil updates[:contact_url]
  end

  test "build_web_updates ignores primary data when page match is unverified" do
    customer = Customer.create!(company: "株式会社安井")
    company = {
      company: "会社概要",
      title: "会社概要",
      url: "https://www.kanban-ichiba.co.jp/company/",
      source: "organic"
    }

    updates = BrightData::Pipeline.send(
      :build_web_updates,
      customer,
      company,
      {
        matched: nil,
        tel: "03-0000-0000",
        address: "東京都中央区銀座1-1-1",
        contact_url: "https://www.kanban-ichiba.co.jp/contact/"
      }
    )

    assert_empty updates
  end

  test "build_web_updates never trusts SERP title after page mismatch" do
    customer = Customer.create!(company: "RST株式会社")
    company = {
      company: "株式会社RST",
      title: "株式会社RST",
      url: "https://rst-inc.net/",
      source: "organic"
    }

    updates = BrightData::Pipeline.send(
      :build_web_updates,
      customer,
      company,
      {
        matched: false,
        source_url: "https://rst-inc.net/",
        address: "東京都渋谷区1-1-1"
      }
    )

    assert_empty updates
  end

  test "build_web_updates rejects cross company contact urls" do
    customer = Customer.create!(company: "株式会社TEAMS")
    company = {
      company: "株式会社TEAMS",
      title: "株式会社TEAMS",
      url: "https://www.teams-t.com/company/",
      source: "organic"
    }

    updates = BrightData::Pipeline.send(
      :build_web_updates,
      customer,
      company,
      {
        matched: true,
        contact_url: "https://www.thinkrun.co.jp/inquiry/"
      }
    )

    refute_includes updates.keys, :contact_url
  end

  test "build_web_updates allows same root contact subdomains" do
    customer = Customer.create!(company: "ヒューマンリソシア株式会社")
    company = {
      company: "ヒューマンリソシア株式会社",
      title: "ヒューマンリソシア株式会社",
      url: "https://corporate.resocia.jp/ourinfo",
      source: "organic"
    }

    updates = BrightData::Pipeline.send(
      :build_web_updates,
      customer,
      company,
      {
        matched: true,
        contact_url: "https://contact.resocia.jp/form/?form_cat=1"
      }
    )

    assert_equal "https://contact.resocia.jp/form/?form_cat=1", updates[:contact_url]
  end

  test "build_web_updates rejects malformed extracted contact urls" do
    customer = Customer.create!(company: "Bad Contact Target")
    company = {
      company: "Bad Contact Target",
      url: "https://example.com/company/",
      source: "organic"
    }

    updates = BrightData::Pipeline.send(
      :build_web_updates,
      customer,
      company,
      { matched: true, contact_url: "[homeurl]/p_privacy?contact=1" }
    )

    refute_includes updates.keys, :contact_url
  end

  test "build_web_updates resolves existing relative contact urls" do
    customer = Customer.create!(
      company: "Relative Contact Target",
      url: "https://example.com/company/",
      contact_url: "../contact/"
    )
    company = {
      company: "Relative Contact Target",
      url: "https://example.com/company/",
      source: "organic"
    }

    updates = BrightData::Pipeline.send(
      :build_web_updates,
      customer,
      company,
      { matched: true }
    )

    assert_equal "https://example.com/contact/", updates[:contact_url]
  end

  test "better_address prefers street address over station access text" do
    assert BrightData::Pipeline.send(
      :better_address?,
      "福岡県筑紫野市大字諸田174-2",
      "福岡県 筑紫野市 桜台駅 徒歩8分"
    )
  end

  test "better_address rejects city level marketing phrases" do
    refute BrightData::Pipeline.send(
      :better_address?,
      "愛知県知立市の軽貨物運送会社",
      "大阪府"
    )
  end

  test "better_address replaces json ld fragments" do
    assert BrightData::Pipeline.send(
      :better_address?,
      "埼玉県富士見市渡戸2-4-24",
      "埼玉県富士見市の軽貨物運送業\",\"potentialAction\":[{\"urlTemplate\":\"https://example.com\"}"
    )
  end

  test "better_address replaces trailing business category text" do
    assert BrightData::Pipeline.send(
      :better_address?,
      "大阪府大阪市東成区玉津1丁目1-8",
      "大阪府大阪市東成区玉津1丁目1-8 建　築"
    )
  end

  test "better_address replaces trailing business description text" do
    assert BrightData::Pipeline.send(
      :better_address?,
      "大阪府大阪市中央区宗右衛門町1-9",
      "大阪府大阪市中央区宗右衛門町1-9 有料職業紹介事業 WEB広告事業 デジタルサイネージ事業 ©"
    )
  end

  test "better_address replaces existing address that cleans to the same candidate" do
    assert BrightData::Pipeline.send(
      :better_address?,
      "埼玉県川越市 下赤坂1800-3",
      "埼玉県川越市 下赤坂1800-3芳野台工場 川越市芳野台1-103-17"
    )
  end

  test "address_score rejects noisy address tails used by the UI" do
    noisy = [
      "神奈川県相模原市南区若松 荷物積み込み場 神奈川県相模原市南区若松 時間 8時から20時",
      "大阪府大阪市中央区城見1-2-27　クリスタルタワー 3F 役員 代表取締役会長",
      "神奈川県横浜市港北区新羽町673-1法人営業部〒223-0057神奈川県横浜市港北区新羽町673-1",
      "福岡県〒805－8528 北九州市八幡東区平野二丁目11番1号",
      "東京都大田区羽田 5丁目3番1号 スカイプラザオフィス12階 GOOGLE Map サイトマップ",
      "神奈川県横浜市青葉区市ヶ尾町1737 店　舗 市ヶ尾店・鴨志田店",
      "神奈川県横浜市鶴見区栄町通１丁目５−１２chinen.alliance_at_bh.wakwak.com",
      "神奈川県下27の自治体・行政区に拡がっています。（2024年4月現在）",
      "大阪府大阪市住之江区御崎6-3-1 吉川ロジスティクスグループビル内3階 MAP",
      "神奈川県川崎市川崎区駅前本町１１番地２　川崎フロンティアビル４F【代表",
      "神奈川県高座郡寒川町一之宮5-10-6 湘南BASE R103【",
      "神奈川県川崎市高津区梶ケ谷6丁目17-4 Go to top ↑",
      "東京都町田市鶴間3-4-1グランベリーパークセントラルコート3FL302代表小林大輝HOMEkeyboard_arrow_rightCOMPANY",
      "熊本県熊本市中央区島崎1丁目1-19本店〒870-0917大分市高松1丁目7番36号　サンシャイン高城 1F"
    ]

    noisy.each do |address|
      assert_equal 0, BrightData::Pipeline.send(:address_score, address), "#{address} should be treated as insufficient"
    end
  end

  test "address_score accepts clear street addresses" do
    assert_operator BrightData::Pipeline.send(
      :address_score,
      "山口県下関市形山みどり町2-11-4"
    ), :>, 0
  end

  test "better_address rejects candidates from a different prefecture" do
    refute BrightData::Pipeline.send(
      :better_address?,
      "東京都八王子市上柚木3-16-4-210",
      "神奈川県 相模原市 中央区"
    )
  end

  test "build_web_updates accepts verified headquarters when candidate address differs from current location" do
    customer = Customer.create!(
      company: "合同会社アイズ",
      address: "神奈川県 相模原市 中央区"
    )
    company = {
      company: "合同会社アイズ",
      title: "合同会社アイズ 会社概要",
      url: "https://www.aizu-hp.com/company",
      source: "organic"
    }

    updates = BrightData::Pipeline.send(
      :build_web_updates,
      customer,
      company,
      {
        matched: true,
        source_url: "https://www.aizu-hp.com/company",
        tel: "080-5484-1683",
        address: "東京都八王子市上柚木3-16-4-210",
        contact_url: "https://www.aizu-hp.com/contact"
      }
    )

    assert_equal "https://www.aizu-hp.com/company", updates[:url]
    assert_equal "080-5484-1683", updates[:tel]
    assert_equal "東京都八王子市上柚木3-16-4-210", updates[:address]
    assert_equal "https://www.aizu-hp.com/contact", updates[:contact_url]
  end

  test "build_web_updates accepts headquarters tel and address when branch-specific office is not found" do
    customer = Customer.create!(
      company: "株式会社CARAVEL 横浜市戸塚区",
      address: "神奈川県 横浜市 戸塚区"
    )
    company = {
      company: "株式会社CARAVEL",
      title: "株式会社CARAVEL",
      url: "https://caravel-driver.com/",
      source: "organic"
    }

    updates = BrightData::Pipeline.send(
      :build_web_updates,
      customer,
      company,
      {
        matched: true,
        source_url: "https://caravel-driver.com/",
        tel: "080-2015-5571",
        address: "神奈川県小田原市浜町2-5-5",
        contact_url: "https://caravel-driver.com/contact/"
      }
    )

    assert_equal "https://caravel-driver.com/", updates[:url]
    assert_equal "080-2015-5571", updates[:tel]
    assert_equal "神奈川県小田原市浜町2-5-5", updates[:address]
    assert_equal "https://caravel-driver.com/contact/", updates[:contact_url]
  end

  test "build_web_updates prefers verified official profile address on close scores" do
    customer = Customer.create!(
      company: "株式会社ホートー",
      address: "埼玉県川越市芳野台1-103-17",
      url: "http://www.hoto.co.jp/"
    )
    company = {
      company: "株式会社ホートー",
      title: "株式会社ホートー",
      url: "http://www.hoto.co.jp/",
      source: "organic"
    }

    updates = BrightData::Pipeline.send(
      :build_web_updates,
      customer,
      company,
      {
        matched: true,
        source_url: "http://hoto.co.jp/Cinfo.html",
        tel: "049-245-9161",
        address: "埼玉県 川越市 下赤坂1800-3"
      }
    )

    assert_equal "埼玉県川越市 下赤坂1800-3", updates[:address]
  end

  test "build_web_updates replaces secondary existing url when source has primary data" do
    customer = Customer.create!(
      company: "株式会社CARAVEL 横浜市戸塚区",
      address: "神奈川県 横浜市 戸塚区",
      url: "https://caravel-driver.com/",
      contact_url: "https://caravel-driver.com/contact/"
    )
    company = {
      company: "株式会社CARAVEL",
      title: "神奈川県の軽貨物配送 ― 株式会社CARAVEL",
      url: "https://caravel-ltd.com/",
      source: "organic"
    }

    updates = BrightData::Pipeline.send(
      :build_web_updates,
      customer,
      company,
      {
        matched: true,
        source_url: "https://caravel-ltd.com/",
        tel: "0465-43-7046",
        address: "神奈川県小田原市浜町2丁目5-5",
        contact_url: "https://caravel-ltd.com/contact/"
      }
    )

    assert_equal "https://caravel-ltd.com/", updates[:url]
    assert_equal "0465-43-7046", updates[:tel]
    assert_equal "神奈川県小田原市浜町2丁目5-5", updates[:address]
    assert_equal "https://caravel-ltd.com/contact/", updates[:contact_url]
  end

  test "web enrichment retry prefers a later matched primary result" do
    assert BrightData::Pipeline.send(:web_enrichment_retry_needed?, { matched: false })
    assert BrightData::Pipeline.send(
      :web_enrichment_result_better?,
      { matched: true, tel: "048-720-8437", address: "埼玉県川口市鳩ヶ谷本町2-14-6" },
      { matched: false }
    )
  end

  test "candidate_priority prefers company overview over office listing for non branch warehouse noise" do
    customer = Customer.new(company: "株式会社博運社倉庫")
    office_listing = { url: "https://www.hus.co.jp/kaisyaannai/jigyosyoannai/" }
    overview = { url: "https://www.hus.co.jp/kaisyaannai/kaishagaiyo/" }

    overview_score = BrightData::Pipeline.send(:candidate_priority, customer, overview, 1)
    office_score = BrightData::Pipeline.send(:candidate_priority, customer, office_listing, 0)

    assert_operator overview_score[0], :<, office_score[0]
  end

  test "candidate_priority prefers official facility page for facility-like customer names" do
    customer = Customer.new(company: "株式会社ふれあい広場 ふれあい多居夢 蕨")
    facility = { url: "https://www.fureai-hiroba.co.jp/facility/fureaitaimu-warabi/" }
    overview = { url: "https://www.fureai-hiroba.co.jp/aboutus/" }

    facility_score = BrightData::Pipeline.send(:candidate_priority, customer, facility, 1)
    overview_score = BrightData::Pipeline.send(:candidate_priority, customer, overview, 0)

    assert_operator facility_score[0], :<, overview_score[0]
  end

  test "search_address_for_query does not let station access text dominate searches" do
    assert_equal "埼玉県", BrightData::Pipeline.send(:search_address_for_query, "埼玉県 草加市 新田駅 車12分")
  end

  test "url policy excludes freejob recruitment pages" do
    assert BrightData::UrlPolicy.excluded_url?(
      "https://freejob.work/FJAC33030296284/",
      title: "株式会社U-platinum 配送ドライバー 求人"
    )
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

  test "execute_from_db normalizes noisy department names in search query" do
    customer = Customer.create!(company: "ドライバーズサポート株式会社宅配課", address: "大阪府 茨木市")

    captured_queries = []
    fake_client = Object.new
    fake_client.define_singleton_method(:batch_search) do |queries, delay_between: 1|
      captured_queries.replace(queries)
      queries.map { |query| { "query" => query, "result" => {}, "timestamp" => Time.current.iso8601 } }
    end

    with_singleton_method(BrightData::SerpClient, :new, -> { fake_client }) do
      with_singleton_method(BrightData::ResultStore, :save_batch, ->(_batch) {}) do
        BrightData::Pipeline.execute_from_db(limit: 1, customer_ids: [customer.id], dry_run: true)
      end
    end

    assert_equal ["ドライバーズサポート株式会社 大阪府 茨木市 会社概要"], captured_queries
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

  test "execute_from_db honors explicit customer ids even when already complete" do
    customer = Customer.create!(
      company: "Complete Explicit Target",
      tel: "090-0000-0000",
      address: "Tokyo",
      url: "https://example.com",
      contact_url: "https://example.com/contact",
      serp_status: "serp_done"
    )

    captured_queries = []
    fake_client = Object.new
    fake_client.define_singleton_method(:batch_search) do |queries, delay_between: 1|
      captured_queries.replace(queries)
      queries.map { |query| { "query" => query, "result" => {}, "timestamp" => Time.current.iso8601 } }
    end

    with_singleton_method(BrightData::SerpClient, :new, -> { fake_client }) do
      with_singleton_method(BrightData::ResultStore, :save_batch, ->(_batch) {}) do
        BrightData::Pipeline.execute_from_db(limit: 1, customer_ids: [customer.id], dry_run: true)
      end
    end

    assert_equal 1, captured_queries.size
    assert_match(/\AComplete Explicit Target/, captured_queries.first)
  end

  test "execute_from_db marks all selected rows as error when SERP client returns fatal error" do
    first = Customer.create!(company: "Fatal First Target", address: "Tokyo")
    second = Customer.create!(company: "Fatal Second Target", address: "Osaka")

    fake_client = Object.new
    fake_client.define_singleton_method(:batch_search) do |queries, delay_between: 1|
      [
        {
          "query" => queries.first,
          "result" => { "error" => "HTTP 401: Bright Data authentication failed", "fatal" => true },
          "timestamp" => Time.current.iso8601
        }
      ]
    end

    with_singleton_method(BrightData::SerpClient, :new, -> { fake_client }) do
      with_singleton_method(BrightData::ResultStore, :save_batch, ->(_batch) {}) do
        BrightData::Pipeline.execute_from_db(limit: 2, customer_ids: [first.id, second.id], dry_run: false)
      end
    end

    assert_equal "serp_error", first.reload.serp_status
    assert_equal "serp_error", second.reload.serp_status
  end

  test "execute_from_db logs target companies separately from candidate urls" do
    customer = Customer.create!(company: "株式会社ログ分離", address: "東京都港区芝1-1-1")

    fake_client = Object.new
    fake_client.define_singleton_method(:batch_search) do |queries, delay_between: 1, &progress|
      progress&.call("index" => 0, "total" => queries.size)
      [
        {
          "query" => queries.first,
          "result" => {
            "organic_results" => [
              {
                "title" => "株式会社ログ分離 | 会社概要",
                "link" => "https://log-separation.example/company/"
              }
            ]
          },
          "timestamp" => Time.current.iso8601
        }
      ]
    end

    stdout, = capture_io do
      with_singleton_method(BrightData::SerpClient, :new, -> { fake_client }) do
        with_singleton_method(BrightData::ResultStore, :save_batch, ->(_batch) {}) do
          with_singleton_method(BrightData::ResultExporter, :to_csv, ->(_companies) {}) do
            with_singleton_method(BrightData::ExtractionStats, :record, ->(*_args, **_kwargs) {}) do
              with_singleton_method(BrightData::WebEnricher, :enrich_from_url, ->(url, _customer) { { matched: true, source_url: url } }) do
                BrightData::Pipeline.execute_from_db(limit: 1, customer_ids: [customer.id], dry_run: false)
              end
            end
          end
        end
      end
    end

    assert_includes stdout, "対象企業: 株式会社ログ分離 (ID=#{customer.id}"
    assert_match(/候補URL 1\/1 .*candidate=株式会社ログ分離 url=https:\/\/log-separation\.example\/company\//, stdout)
    refute_includes stdout, "customer=株式会社ログ分離"
  end

  test "execute_from_db saves audit run target results with run id and jid" do
    customer = Customer.create!(company: "Audit Target Company", address: "東京都港区芝1-1")
    run = SerpEnrichmentRun.create_for_targets!(
      run_id: "audit-run-test",
      industry: "",
      limit: 1,
      targets: [customer]
    )

    fake_client = Object.new
    fake_client.define_singleton_method(:batch_search) do |queries, delay_between: 1, &progress|
      progress&.call("index" => 0, "total" => queries.size)
      [
        {
          "query" => queries.first,
          "result" => {
            "organic_results" => [
              {
                "title" => "Audit Target Company | 会社概要",
                "link" => "https://audit-target.example/company/"
              }
            ]
          },
          "timestamp" => Time.current.iso8601
        }
      ]
    end

    stdout, = capture_io do
      with_singleton_method(BrightData::SerpClient, :new, -> { fake_client }) do
        with_singleton_method(BrightData::ResultStore, :save_batch, ->(_batch) {}) do
          with_singleton_method(BrightData::ResultExporter, :to_csv, ->(_companies) {}) do
            with_singleton_method(BrightData::ExtractionStats, :record, ->(*_args, **_kwargs) {}) do
              with_singleton_method(BrightData::WebEnricher, :enrich_from_url, ->(url, _customer) {
                { matched: true, source_url: url, tel: "03-1111-2222", address: "東京都港区芝1-1-1" }
              }) do
                BrightData::Pipeline.execute_from_db(
                  limit: 1,
                  customer_ids: [customer.id],
                  progress_run_id: run.run_id,
                  jid: "jid-audit-1",
                  dry_run: false
                )
              end
            end
          end
        end
      end
    end

    assert_includes stdout, "[SERP run=audit-run-test jid=jid-audit-1]"
    assert_equal "done", run.reload.status
    assert_equal "jid-audit-1", run.jid

    target = run.targets.first.reload
    assert_equal customer.id, target.customer_id
    assert_equal "updated", target.result_status
    assert_equal 1, target.candidate_count
    assert_equal "https://audit-target.example/company/", target.selected_url
    assert_includes target.update_keys, "url"
    assert_equal "serp_done", target.after_serp_status
    assert_equal "03-1111-2222", target.after_tel
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
