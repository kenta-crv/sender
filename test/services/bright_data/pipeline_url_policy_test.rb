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

  test "candidate_priority prefers company overview over office listing for non branch warehouse noise" do
    customer = Customer.new(company: "株式会社博運社倉庫")
    office_listing = { url: "https://www.hus.co.jp/kaisyaannai/jigyosyoannai/" }
    overview = { url: "https://www.hus.co.jp/kaisyaannai/kaishagaiyo/" }

    overview_score = BrightData::Pipeline.send(:candidate_priority, customer, overview, 1)
    office_score = BrightData::Pipeline.send(:candidate_priority, customer, office_listing, 0)

    assert_operator overview_score[0], :<, office_score[0]
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
