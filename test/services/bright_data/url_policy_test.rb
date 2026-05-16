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
      "https://companydata.tsujigawa.com/company2/9290001107947/",
      "https://salesnow.jp/db/companies/jcb8j5xxh0r49u19e",
      "https://www.big-advance.site/c/160/2015/profile",
      "https://job.logiquest.co.jp/jobfind-smartphone/job/4995",
      "https://gaten.info/job/16924",
      "https://jp.ldigi.com.tw/detail.php?ban_no=9120101059122",
      "https://www.24u.jp/0929626301/",
      "https://driver-navi.com/detail/8019/",
      "https://kyujin-ascom.com/detail/?id=153808954",
      "https://townwork.net/company/1078118990/",
      "https://doraever.jp/company/1323716",
      "https://dorapita.com/recruits/company/60041",
      "https://doraducts.jp/contact",
      "https://stagg-recruit.jp/list/osaka/",
      "https://www.hatalike.jp/viewjob/55784276adef433a/",
      "https://www.hatarako.net/company/346355/bases/fukuoka/",
      "https://hyuga-jobnavi.com/whi_job_info/example/",
      "https://clients.itszai.jp/4d5467354f54453d/recruitments/340847?referencenumber=340847",
      "https://www.job-lead.com/inquiry/",
      "https://www.shigotop.com/data.php?c=info&item=10288",
      "https://hakopro.jp/company/83330",
      "https://www.kyotobank.co.jp/houjin/kpa/memberlist/00001176.html",
      "https://goo-help.my.site.com/s/contactsupport",
      "https://untendaikou.co.jp/fukuokaken/driver-9942",
      "https://www.ipros.com/company/detail/2099185/",
      "https://marketing.ipros.jp/inquiry-ipros-ad/",
      "https://www.hoikushibank.com/company/20903",
      "https://map.yahoo.co.jp/v3/place/qpaNDvZK-Fk",
      "https://www.e-arpa.jp/fukuoka/detail.html?jid=300001300001000392415640108001",
      "https://arubaito-next.com/detail/dsaiyo/m8ca/ST0034/612/",
      "https://www.e-aidem.com/aps/02_AD0909207397_detail.htm",
      "https://atcompany.jp/kinkiexp/",
      "https://jmty.jp/osaka/rec-dis/article-198v0r",
      "https://www.cognavi.jp/catalog/110821/000003/",
      "https://info.gbiz.go.jp/hojin/ichiran?hojinBango=1290001046153",
      "https://map.idemitsu.com/b/a/info/0000020614/",
      "https://www.taiyooil.net/ss/search/fukuoka/003825.html",
      "https://ucar.carview.yahoo.co.jp/shop/fukuoka/306898002/",
      "https://www.kensetumap.com/company/461853/profile.php",
      "https://www.lixil-madolier.jp/madolier/pub/merchant/page/MerchantTopPage.df?post_blogdir=5000144",
      "https://metoree.com/companies/78615/",
      "https://web.suke-dachi.jp/cl/fukuoka-033485",
      "https://recyclehub.jp/company/81003712",
      "https://eigyo-mfg.com/service/navi/company/yzBNP9Yz9QS7",
      "http://27.0.41.102/spsite/spcomprofile.html",
      "https://www.city.kitakyushu.lg.jp/contents/25800004.html",
      "https://www.hellonetz.com/shop-info/orio",
      "https://www.j-vgi.co.jp/portfolio/hacobu",
      "https://toiku-shukatsu.net/search/company/TW0480/index.html",
      "https://sue-sho.com/member-introduction/unyu/example/",
      "https://www.zehitomo.com/profile/example/pro",
      "https://kabutan.jp/",
      "https://kabushiki.jp/",
      "https://site0.sbisec.co.jp/marble/domestic/top.do",
      "https://www.rakuten-sec.co.jp/web/domestic/",
      "https://advance.quote.nomura.co.jp/meigara/nomura2/qsearch.exe",
      "http://www.okasan.co.jp/start/beginner/stock/about.html",
      "https://jobcatalog.yahoo.co.jp/company/1500185239/information/",
      "https://corp.daijob.com/company/outline",
      "https://www.osibori.co.jp/zenkoku/kanagawa/tanikawa/tanikawa.htm",
      "https://guts-rentacar.com/shop/kanagawa/hiyoshi/",
      "https://shimbuns.com/contact/",
      "https://musashikosugi.blog.shinobi.jp/Entry/2359/",
      "https://www.ecareer.ne.jp/positions/00054119001/25",
      "https://sftworks.jp/detail/519540/X00617862800000",
      "https://founded-today.com/2025/1020003029983/",
      "https://shikaku-job.biz/shop/184587",
      "https://suumo.jp/chintai/jnc_000104778261/",
      "https://www.homemate-research-discount-shop.com/dtl/00000000000000213885/",
      "https://shougai.rakuraku.or.jp/result/detail.html?djgno=1450900087",
      "https://x-work.jp/driver/media_90529",
      "https://www.nisshinfire.co.jp/agency/shop/kanagawa.html"
    ]

    rejected.each do |url|
      assert BrightData::UrlPolicy.excluded_url?(url), "#{url} should be excluded"
    end
  end

  test "official_url? rejects noisy titles and paths" do
    assert BrightData::UrlPolicy.excluded_url?("https://example.com/company", title: "株式会社ABCの転職・企業概要")
    assert BrightData::UrlPolicy.excluded_url?("https://example.com/recruit/", title: "株式会社ABC 採用情報")
  end

  test "official_url? rejects relative paths" do
    refute BrightData::UrlPolicy.official_url?("/contact")
    refute BrightData::UrlPolicy.official_url?("#contact")
  end

  test "normalize_company_name removes SERP title noise" do
    assert_equal "株式会社第一プラテック", BrightData::UrlPolicy.normalize_company_name("株式会社第一プラテックの転職・企業概要")
    assert_equal "株式会社第一プラテック", BrightData::UrlPolicy.normalize_company_name("株式会社第一プラテック(法人番号")
    assert_equal "株式会社ZOOOM TRANSPORT", BrightData::UrlPolicy.normalize_company_name("株式会社ZOOOM TRANSPORT(大阪府大東市)の企業詳細")
    assert_equal "株式会社STAG", BrightData::UrlPolicy.normalize_company_name("株式会社STAGの会社概要【2026年最新】")
    assert_equal "株式会社ライフプラテック", BrightData::UrlPolicy.normalize_company_name("株式会社ライフプラテック")
  end

  test "normalize_company_name removes job department noise" do
    assert_equal "ドライバーズサポート株式会社", BrightData::UrlPolicy.normalize_company_name("ドライバーズサポート株式会社宅配課")
    assert_equal "ドライバーズサポート株式会社", BrightData::UrlPolicy.normalize_company_name("業務委託 ドライバーズサポート株式会社/関西支店宅配課")
    assert_equal "株式会社イードライバーズ", BrightData::UrlPolicy.normalize_company_name("株式会社イードライバーズ関西支店")
    assert_equal "ままここびより／株式会社ハーベスト", BrightData::UrlPolicy.normalize_company_name("ままここびより／株式会社ハーベスト")
  end
end
