# frozen_string_literal: true

require "uri"

module BrightData
  # SERPで取得した企業URLから会社情報を補完するサービス
  #
  # 処理フロー:
  #   1. トップページを HTTP GET (CompanyInfoExtractor.fetch_and_parse)
  #   2. 会社名マッチング検証（誤マッチ防止）
  #   3. 「会社概要」等のプロフィールページリンクを探してリダイレクト
  #   4. プロフィールページを再取得して tel / address / company / contact_url を抽出
  #
  # 戻り値の :matched キー:
  #   true  … 会社名が一致確認済み
  #   false … 不一致（呼び出し側でスキップ）
  #   nil   … 検証不能（ページから会社名を取得できず）
  class WebEnricher
    # ── ディレクトリサイト除外リスト ──
    # url として保存すべきでない企業ディレクトリ・レビューサイト
    DIRECTORY_DOMAINS = %w[
      cnavi.g-search.or.jp
      en-hyouban.com
      baseconnect.in
      houjin.jp
      houjin-bangou.nta.go.jp
      alarmbox.jp
      mapion.co.jp
      navitime.co.jp
      itp.ne.jp
      ekiten.jp
      tdb.co.jp
      dun.co.jp
      nikkei.com
      job-medley.com
      openwork.jp
      vorkers.com
      bunshun.jp
      diamond.jp
      r.gnavi.co.jp
      tabelog.com
      hotpepper.jp
      homes.co.jp
      suumo.jp
      minkabu.jp
      yahoo.co.jp
      yelp.co.jp
    ].freeze

    PROFILE_LINK_TEXT = /会社概要|企業概要|企業情報|会社案内|会社情報|会社紹介|コーポレート|about\s*us|about\s*company/i

    PROFILE_LINK_PATH = /\/company(?:-info|-profile|-about)?(?:\/|\.html?)?$|
                          \/about(?:-us)?(?:\/|\.html?)?$|
                          \/profile(?:\/|\.html?)?$|
                          \/corp(?:orate)?(?:\/|\.html?)?$|
                          \/kaisha(?:gaiyou)?(?:\/|\.html?)?$|
                          \/kigyou(?:jouhou)?(?:\/|\.html?)?$/xi

    # ── 正規化用パターン ──

    # 法人格（前置・後置とも）
    CORP_REGEX = /株式会社|\(株\)|（株）|有限会社|\(有\)|（有）|合同会社|合資会社|
                  一般社団法人|一般財団法人|社会福祉法人|医療法人|学校法人|
                  特定非営利活動法人|NPO法人|
                  co\.,?\s*ltd\.?|inc\.?|corp\.?|llc\.?/ix

    # 敬称・肩書き
    HONORIFIC_REGEX = /御中|様\z/

    # 支店・営業所等（末尾に出現するもの）
    BRANCH_REGEX = /(?:\S{1,10}(?:支店|営業所|出張所|オフィス|事業所|本店|本社|支社|事務所|店))\z/

    # @param url [String]
    # @param customer [Customer|OpenStruct|nil]
    # @return [Hash]  :matched => true|false|nil, その他 :tel/:address/:contact_url/:company
    def self.enrich_from_url(url, customer = nil)
      # 1. トップページを取得
      top_extractor = CompanyInfoExtractor.fetch_and_parse(url, customer: customer)
      if top_extractor.nil?
        Rails.logger.warn("[WebEnricher] トップページ取得失敗: #{url}")
        return { matched: false }
      end

      # 2. 会社名マッチング検証
      matched_flag = nil
      if customer&.company.present?
        norm_customer = normalize_company(customer.company)

        # まず法人格付き会社名をページから抽出して比較
        page_company = extract_page_company(top_extractor.doc)
        if page_company.present?
          norm_page = normalize_company(page_company)
          matched_flag = company_match?(norm_customer, norm_page)

          if matched_flag
            puts "  [WebEnricher] match check: '#{norm_customer}' ⊆ '#{norm_page}' → MATCH"
          else
            puts "  [WebEnricher] mismatch: '#{norm_customer}' vs '#{norm_page}' → SKIP"
            return { matched: false }
          end
        else
          # ページから法人名を抽出できなかった場合: title/h1 で確認
          name_found = customer_name_in_page?(top_extractor.doc, norm_customer)
          if name_found == false
            puts "  [WebEnricher] mismatch: '#{norm_customer}' not found in page → SKIP"
            return { matched: false }
          else
            matched_flag = nil
            puts "  [WebEnricher] company not detected on page, #{name_found ? 'name found in text' : 'proceeding'}"
          end
        end
      end

      # 3. 会社概要ページのリンクを探す
      profile_url = find_profile_link(top_extractor.doc, url)
      puts "  [WebEnricher] profile_url: #{profile_url || '(not found, using top page)'}"

      # 4. 会社概要ページを取得
      target_extractor = if profile_url.present? && profile_url != url
        CompanyInfoExtractor.fetch_and_parse(profile_url, customer: customer) || top_extractor
      else
        top_extractor
      end

      # 5. 情報を抽出して :matched を付加して返す
      result = target_extractor.extract.merge(matched: matched_flag)

      # contact_url を絶対URLに変換
      if result[:contact_url].present?
        base = profile_url.presence || url
        result[:contact_url] = resolve_contact_url(result[:contact_url], base)
      end

      result
    rescue => e
      Rails.logger.warn("[WebEnricher] enrich_from_url error for #{url}: #{e.message}")
      { matched: false }
    end

    private

    # ── 会社名の正規化 ──
    # 法人格・敬称・支店情報・記号・スペースを除去し、小文字化して返す
    def self.normalize_company(name)
      s = name.to_s.dup

      # 全角英数 → 半角
      s = s.tr("Ａ-Ｚａ-ｚ０-９", "A-Za-z0-9")

      # 法人格を除去
      s.gsub!(CORP_REGEX, "")
      # 敬称を除去
      s.gsub!(HONORIFIC_REGEX, "")
      # 支店・営業所等を除去（末尾）
      s.gsub!(BRANCH_REGEX, "")
      # 記号・スペースを除去
      s.gsub!(/[\s　・\-－ー＝=\.,、。()（）\[\]「」【】\|\/]/, "")

      s.downcase.strip
    end

    # ── マッチ判定 ──
    # 正規化済みの2つの名前で双方向 containment を判定する。
    # 短い方が3文字以上であれば、一方が他方に含まれていれば OK。
    # 3文字未満の場合は完全一致のみ。
    def self.company_match?(norm_a, norm_b)
      return false if norm_a.empty? || norm_b.empty?
      return true  if norm_a == norm_b

      shorter, longer = [norm_a, norm_b].sort_by(&:length)

      if shorter.length >= 3
        longer.include?(shorter)
      else
        false  # 3文字未満は完全一致のみ（上でチェック済み）
      end
    end

    # ── ページの運営企業名を抽出する ──
    def self.extract_page_company(doc)
      candidates = []

      candidates << extract_corp_name(doc.at("title")&.text.to_s.strip)

      doc.css("h1").first(3).each { |h| candidates << extract_corp_name(h.text.strip) }

      if (footer = doc.at("footer"))
        ft = footer.text.gsub(/\s+/, " ").strip
        m = ft.match(/(?:©|copyright)[^\n]{0,15}?((?:株式会社|有限会社|合同会社)\s*\S+)/i)
        candidates << m[1].strip if m
        candidates << extract_corp_name(ft)
      end

      if (header = doc.at("header"))
        candidates << extract_corp_name(header.text.strip)
      end

      meta = doc.at("meta[name='description']")&.[]("content").to_s.strip
      candidates << extract_corp_name(meta) if meta.present?

      candidates.compact.reject(&:empty?).first
    end

    # テキストから最初の法人格付き会社名を抽出する
    def self.extract_corp_name(text)
      return nil if text.blank?

      m = text.match(/(?:株式会社|有限会社|合同会社|一般社団法人|一般財団法人)\s*\S+/)
      return m[0].gsub(/[[:space:]]/, "") if m

      m2 = text.match(/\S+(?:株式会社|有限会社|合同会社)/)
      return m2[0].strip if m2

      m3 = text.match(/[A-Z][A-Za-z0-9\s&'\-]{1,25}(?:,?\s*(?:Inc|Corp|LLC|Co|Ltd)\.?)+/i)
      m3 ? m3[0].strip : nil
    end

    # 顧客の正規化名がページの title/h1/h2 に含まれるか確認
    def self.customer_name_in_page?(doc, norm_customer)
      return nil if norm_customer.length < 3

      sources = [
        doc.at("title")&.text.to_s,
        *doc.css("h1").map(&:text),
        *doc.css("h2").first(2).map(&:text),
      ]

      sources.each do |src|
        norm_src = normalize_company(src)
        return true if company_match?(norm_customer, norm_src)
      end

      false
    end

    # ── URL ユーティリティ ──

    def self.find_profile_link(doc, base_url)
      base_uri = URI.parse(base_url) rescue nil
      return nil if base_uri.nil?
      base_host = base_uri.host.to_s.sub(/\Awww\./, "")

      doc.css("a[href]").each do |a|
        href = a["href"].to_s.strip
        text = a.text.strip

        next if href.blank?
        next if href.start_with?("javascript:", "mailto:", "tel:", "#")
        next if text.match?(/採用|求人|recruit|login|logout|ブログ|blog|news|ニュース/i)

        if text.match?(PROFILE_LINK_TEXT) || href.match?(PROFILE_LINK_PATH)
          resolved = resolve_url(href, base_uri)
          next if resolved.nil?
          target_uri = URI.parse(resolved) rescue nil
          next if target_uri.nil?
          target_host = target_uri.host.to_s.sub(/\Awww\./, "")
          next unless target_host == base_host
          return resolved
        end
      end
      nil
    end

    # ディレクトリサイトかどうか判定
    def self.directory_url?(url)
      uri = URI.parse(url) rescue nil
      return false if uri.nil? || uri.host.nil?
      host = uri.host.downcase.sub(/\Awww\./, "")
      DIRECTORY_DOMAINS.any? { |d| host == d || host.end_with?(".#{d}") }
    end

    # contact_url を絶対URLに変換する
    def self.resolve_contact_url(contact_url, base_url)
      return nil if contact_url.blank?

      # 既に絶対URLなら何もしない
      return contact_url if contact_url.start_with?("http://", "https://")

      base_uri = URI.parse(base_url) rescue nil
      return contact_url if base_uri.nil?

      if contact_url.start_with?("#")
        # フラグメントのみ → ページ自身のURLにフラグメントを付与
        "#{base_uri.scheme}://#{base_uri.host}#{base_uri.path}#{contact_url}"
      elsif contact_url.start_with?("//")
        "#{base_uri.scheme}:#{contact_url}"
      elsif contact_url.start_with?("/")
        "#{base_uri.scheme}://#{base_uri.host}#{contact_url}"
      else
        # 相対パス（"./contact.html" や "contact.html"）
        base_path = base_uri.path.sub(%r{/[^/]*\z}, "/")
        clean = contact_url.sub(%r{\A\./}, "")
        "#{base_uri.scheme}://#{base_uri.host}#{base_path}#{clean}"
      end
    rescue URI::InvalidURIError
      contact_url
    end

    def self.resolve_url(href, base_uri)
      if href.start_with?("http://", "https://")
        href
      elsif href.start_with?("//")
        "#{base_uri.scheme}:#{href}"
      elsif href.start_with?("/")
        "#{base_uri.scheme}://#{base_uri.host}#{href}"
      elsif href.present?
        "#{base_uri.scheme}://#{base_uri.host}/#{href.sub(/\A\.\//, '')}"
      end
    end
  end
end
