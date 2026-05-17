# frozen_string_literal: true

require "cgi"
require "uri"

module BrightData
  class UrlPolicy
    RECRUIT_DOMAINS = %w[
      doda.jp
      syukatsu-kaigi.jp
      wantedly.com
      indeed.com
      en-gage.net
      rikunabi.com
      mynavi.jp
      en-japan.com
      workport.co.jp
      baitoru.com
      gaten.info
      saiyo-connect.jp
      jbplt.jp
      job-medley.com
      job.logiquest.co.jp
      lacotto.jp
      xn--pckua2a7gp15o89zb.com
      kyujin-ascom.com
      toranet.jp
      townwork.net
      doraever.jp
      dorapita.com
      doraducts.jp
      hellowork.mhlw.go.jp
      stagg-recruit.jp
      hatalike.jp
      hatarako.net
      stanby.com
      gigabaito.com
      hyuga-jobnavi.com
      itszai.jp
      job-lead.com
      shigotop.com
      e-arpa.jp
      arubaito-next.com
      hoikushibank.com
      e-aidem.com
      saiyo.page
      saiyo-kakaricho.com
      atcompany.jp
      jmty.jp
      cognavi.jp
      gourmetcaree.jp
      massmedian.co.jp
      jobcatalog.yahoo.co.jp
      doraever-match.jp
      daijob.com
      ecareer.ne.jp
      employment.en-japan.com
      r-agent.com
      sftworks.jp
      shikaku-job.biz
      type.jp
      x-work.jp
    ].freeze

    DIRECTORY_DOMAINS = %w[
      houjin.jp
      houjin-bangou.nta.go.jp
      toukibo.ai-con.lawyer
      bebee.com
      b-mall.ne.jp
      buffett-code.com
      cnavi.g-search.or.jp
      g-search.or.jp
      alarmbox.jp
      baseconnect.in
      biz-maps.com
      big-advance.site
      companydata.tsujigawa.com
      tsujigawa.com
      salesnow.jp
      navitime.co.jp
      mapion.co.jp
      itp.ne.jp
      ekiten.jp
      en-hyouban.com
      e-sogi.com
      tdb.co.jp
      dun.co.jp
      nikkei.com
      openwork.jp
      vorkers.com
      works.aqsh.co.jp
      fc-hikaku.net
      mono.ipros.com
      ipros.com
      ipros.jp
      tryworkneo.net
      annai-center.com
      daikonavi.com
      goo-net.com
      goo-help.my.site.com
      ldigi.com.tw
      osaka-fc.jp
      grip.website
      tsukulink.net
      toushiikusei.net
      shachomeikan.jp
      24u.jp
      driver-navi.com
      booking.com
      hakopro.jp
      mlit.go.jp
      kyotobank.co.jp
      untendaikou.co.jp
      map.yahoo.co.jp
      kosodate-mise.pref.fukuoka.lg.jp
      rehome-navi.com
      hentaishinshi.xyz
      gbiz.go.jp
      map.idemitsu.com
      taiyooil.net
      carview.yahoo.co.jp
      kensetumap.com
      lixil-madolier.jp
      metoree.com
      recyclehub.jp
      suke-dachi.jp
      eigyo-mfg.com
      city.kitakyushu.lg.jp
      hellonetz.com
      j-vgi.co.jp
      toiku-shukatsu.net
      sue-sho.com
      zehitomo.com
      yourmystar.jp
      jgoodtech.smrj.go.jp
      shinkin.co.jp
      kabutan.jp
      kabushiki.jp
      sbisec.co.jp
      rakuten-sec.co.jp
      nomura.co.jp
      okasan.co.jp
      osibori.co.jp
      guts-rentacar.com
      shimbuns.com
      blog.shinobi.jp
      founded-today.com
      suumo.jp
      homemate-research-discount-shop.com
      shougai.rakuraku.or.jp
    ].freeze

    SOCIAL_DOMAINS = %w[
      twitter.com
      x.com
      facebook.com
      instagram.com
      note.com
      prtimes.jp
      wikipedia.org
      google.com
    ].freeze

    DOCUMENT_PATTERN = /\.(?:pdf|xlsx?|csv|docx?)(?:\?|#|\z)/i
    JOB_PATH_PATTERN = %r{/(?:jobfind|job[_-]?offers?|jobs?|recruit|career|saiyo)(?:[-_/]|\z)}i
    DIRECTORY_PATH_PATTERN = %r{/agency/shop(?:/|\?|$)|/driver/media_[0-9]+}i
    EXCLUDED_TEXT_PATTERN = /
      転職|求人|採用|バイト|アルバイト|(?<![ァ-ヶー])パート(?![ァ-ヶー])|
      本選考|エントリーシート|(?<![A-Za-z])ES(?![A-Za-z])|
      評判|口コミ|法人番号|インボイス|会社の評判|企業詳細|企業データ分析
    /ix

    COMPANY_NOISE_PATTERNS = [
      /\A(?:業務委託|正社員|契約社員|派遣社員|アルバイト|パート)\s+/,
      %r{[\/／]\s*[^\/／]*(?:支店|営業所|出張所|オフィス|事業所|本店|本社|支社|事務所)?[^\/／]*(?:宅配課|配送課|配達課|営業課|総務課|事務課|管理課|採用課|人事課|物流課|運送課|営業部|総務部|人事部|管理部|物流部|運送部|センター).*\z},
      /\s*(?:北海道|東北|北関東|南関東|関東|東京|首都圏|東海|中部|北陸|関西|近畿|大阪|京都|神戸|兵庫|中国|四国|九州|福岡|沖縄)(?:支店|営業所|出張所|オフィス|事業所|本店|本社|支社|事務所)\z/,
      /\s*(?:宅配課|配送課|配達課|営業課|総務課|事務課|管理課|採用課|人事課|物流課|運送課|\S{1,12}(?:営業部|総務部|人事部|管理部|物流部|運送部))\z/,
      /[（(]\s*法人番号.*\z/,
      /[（(][^）)]*(?:都|道|府|県|市|区|町|村)[^）)]*[）)]?\s*の?(?:企業詳細|企業情報)?.*\z/,
      /\s*の\s*(?:転職・企業概要|転職|企業概要|採用情報|求人情報|企業情報|企業詳細|評判・口コミ|口コミ|運営企業情報).*\z/,
      /\s*の\s*会社概要(?:【[^】]+】)?.*\z/,
      /\s*の\s*本選考.*\z/,
      /\s*(?:転職|求人|採用|バイト|アルバイト|パート)情報.*\z/,
      /\s*[\|｜].*\z/
    ].freeze

    class << self
      def official_url?(url, title: nil)
        !excluded_url?(url, title: title)
      end

      def excluded_url?(url, title: nil)
        uri = parse_http_url(url)
        return true if uri.nil?

        host = normalized_host(uri.host)
        return true if ip_address_host?(host)
        return true if excluded_domain?(host)
        return true if uri.to_s.match?(DOCUMENT_PATTERN)
        return true if decoded_path_and_query(uri).match?(JOB_PATH_PATTERN)
        return true if decoded_path_and_query(uri).match?(DIRECTORY_PATH_PATTERN)

        text = [title, decoded_path_and_query(uri)].compact.join(" ")
        text.match?(EXCLUDED_TEXT_PATTERN)
      end

      def excluded_domain?(host)
        normalized = normalized_host(host)
        all_excluded_domains.any? { |domain| normalized == domain || normalized.end_with?(".#{domain}") }
      end

      def normalize_company_name(name)
        value = name.to_s.tr("　", " ").strip.gsub(/\s+/, " ")
        return nil if value.blank?

        value = value.gsub(/[（(]株[）)]/, "株式会社")
                     .gsub(/[（(]有[）)]/, "有限会社")
                     .gsub(/[（(]合[）)]/, "合同会社")
        COMPANY_NOISE_PATTERNS.each { |pattern| value = value.sub(pattern, "") }
        value = value.gsub(/\s+/, " ")
                     .gsub(/[、。・\s　]+?\z/, "")
                     .gsub(/[（(「【\[]+\z/, "")
                     .strip

        value.presence
      end

      private

      def all_excluded_domains
        RECRUIT_DOMAINS + DIRECTORY_DOMAINS + SOCIAL_DOMAINS
      end

      def parse_http_url(url)
        return nil if url.blank?

        value = url.to_s.strip
        return nil if value.start_with?("/", "#")

        value = "https://#{value}" unless value.match?(%r{\Ahttps?://}i)
        uri = URI.parse(value)
        return nil unless uri.is_a?(URI::HTTP) && uri.host.present?

        uri
      rescue URI::InvalidURIError
        nil
      end

      def normalized_host(host)
        host.to_s.downcase.sub(/\Awww\./, "")
      end

      def ip_address_host?(host)
        host.to_s.match?(/\A\d{1,3}(?:\.\d{1,3}){3}\z/)
      end

      def decoded_path_and_query(uri)
        raw = [uri.path, uri.query].compact.join(" ")
        CGI.unescape(raw)
      rescue ArgumentError
        raw
      end
    end
  end
end
