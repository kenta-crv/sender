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
      saiyo-connect.jp
      jbplt.jp
      job-medley.com
      xn--pckua2a7gp15o89zb.com
    ].freeze

    DIRECTORY_DOMAINS = %w[
      houjin.jp
      houjin-bangou.nta.go.jp
      toukibo.ai-con.lawyer
      buffett-code.com
      cnavi.g-search.or.jp
      alarmbox.jp
      baseconnect.in
      biz-maps.com
      salesnow.jp
      navitime.co.jp
      mapion.co.jp
      itp.ne.jp
      ekiten.jp
      en-hyouban.com
      tdb.co.jp
      dun.co.jp
      nikkei.com
      openwork.jp
      vorkers.com
      works.aqsh.co.jp
      fc-hikaku.net
      mono.ipros.com
      tryworkneo.net
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
    EXCLUDED_TEXT_PATTERN = /
      転職|求人|採用|バイト|アルバイト|パート|
      本選考|エントリーシート|(?<![A-Za-z])ES(?![A-Za-z])|
      評判|口コミ|法人番号|インボイス|会社の評判|企業詳細|企業データ分析
    /ix

    COMPANY_NOISE_PATTERNS = [
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
        return true if excluded_domain?(host)
        return true if uri.to_s.match?(DOCUMENT_PATTERN)

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

      def decoded_path_and_query(uri)
        raw = [uri.path, uri.query].compact.join(" ")
        CGI.unescape(raw)
      rescue ArgumentError
        raw
      end
    end
  end
end
