# frozen_string_literal: true

require "nokogiri"
require "net/http"
require "uri"
require "openssl"

class CompanyInfoExtractor
  TEL_REGEX = /(?<!\d)(?:0120-\d{3}-\d{3}|0800-\d{3}-\d{4}|0(?:50|70|80|90)-\d{4}-\d{4}|0[36]-\d{4}-\d{4}|0\d{1,4}-\d{1,4}-\d{4})(?!\d)/
  CONTACT_LINK_TEXT = /お問い合わせ|お問合せ|問合せ|contact|inquiry/i
  CONTACT_LINK_PATH = /contact|inquiry|toiawase|otoiawase/i
  NON_CONTACT_LINK_TEXT = /お問い合わせ番号|問合せ番号|送り状|追跡|照会|tracking|trace/i
  NON_CONTACT_LINK_PATH = /webtrace|tracking|trace/i
  BRANCH_TOKEN_REGEX = /\S{1,20}(?:センター|支店|営業所|出張所|オフィス|事業所|本店|本社|支社|工場|店)/
  LEGAL_ENTITY_NAME_REGEX = /(?:株式会社|有限会社|合同会社|一般社団法人|一般財団法人)\s*[A-Za-z0-9一-龥ァ-ヶー&.・\s]{1,60}|[A-Za-z0-9一-龥ァ-ヶー&.・\s]{1,60}(?:株式会社|有限会社|合同会社)/

  PREF_PATTERN = /(?:北海道|青森県|岩手県|宮城県|秋田県|山形県|福島県|茨城県|栃木県|群馬県|
                    埼玉県|千葉県|東京都|神奈川県|新潟県|富山県|石川県|福井県|山梨県|長野県|
                    岐阜県|静岡県|愛知県|三重県|滋賀県|京都府|大阪府|兵庫県|奈良県|和歌山県|
                    鳥取県|島根県|岡山県|広島県|山口県|徳島県|香川県|愛媛県|高知県|福岡県|
                    佐賀県|長崎県|熊本県|大分県|宮崎県|鹿児島県|沖縄県)/x

  ADDRESS_REGEX = /(?:北海道|青森県|岩手県|宮城県|秋田県|山形県|福島県|茨城県|栃木県|群馬県|埼玉県|千葉県|東京都|神奈川県|新潟県|富山県|石川県|福井県|山梨県|長野県|岐阜県|静岡県|愛知県|三重県|滋賀県|京都府|大阪府|兵庫県|奈良県|和歌山県|鳥取県|島根県|岡山県|広島県|山口県|徳島県|香川県|愛媛県|高知県|福岡県|佐賀県|長崎県|熊本県|大分県|宮崎県|鹿児島県|沖縄県)[^\n\r<>「」【】]{5,120}/

  USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

  attr_reader :doc

  def initialize(html, customer: nil)
    @doc = Nokogiri::HTML(html)
    @customer = customer
  end

  # URLからHTTPでHTMLを取得してインスタンスを返す
  # @param url [String]
  # @param customer [Customer|OpenStruct|nil]
  # @return [CompanyInfoExtractor, nil]
  def self.fetch_and_parse(url, customer: nil)
    html = fetch_html(url)
    return nil if html.nil?
    new(html, customer: customer)
  rescue => e
    Rails.logger.warn("[CompanyInfoExtractor] fetch_and_parse error for #{url}: #{e.message}")
    nil
  end

  def self.fetch_and_parse_rendered(url, customer: nil)
    html = fetch_rendered_html(url)
    return nil if html.nil?
    new(html, customer: customer)
  rescue => e
    Rails.logger.warn("[CompanyInfoExtractor] fetch_and_parse_rendered error for #{url}: #{e.message}")
    nil
  end

  def extract
    {
      company: extract_company,
      tel:     extract_tel,
      address: extract_address,
      contact_url: extract_contact_url
    }
  end

  private

  # HTTPでHTMLを取得（リトライ・文字コード自動判定つき）
  def self.fetch_html(url, max_retries: 2)
    attempts = 0
    begin
      attempts += 1
      uri = URI.parse(url)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl     = (uri.scheme == "https")
      http.open_timeout = 15
      http.read_timeout = 15
      # 証明書期限切れ等の古い企業サイト対応
      http.verify_mode = OpenSSL::SSL::VERIFY_NONE

      req = Net::HTTP::Get.new(uri.request_uri)
      req["User-Agent"]      = USER_AGENT
      req["Accept"]          = "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
      req["Accept-Language"] = "ja,en-US;q=0.7,en;q=0.3"

      res = http.request(req)
      code = res.code.to_i

      # 3xx リダイレクトは最大5回追いかける
      redirect_count = 0
      while (300..399).cover?(code) && redirect_count < 5
        location = res["Location"].to_s
        break if location.blank?
        location = "#{uri.scheme}://#{uri.host}#{location}" unless location.start_with?("http")
        uri  = URI.parse(location)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl      = (uri.scheme == "https")
        http.open_timeout = 15
        http.read_timeout = 15
        http.verify_mode  = OpenSSL::SSL::VERIFY_NONE
        req = Net::HTTP::Get.new(uri.request_uri)
        req["User-Agent"]      = USER_AGENT
        req["Accept-Language"] = "ja,en-US;q=0.7,en;q=0.3"
        res = http.request(req)
        code = res.code.to_i
        redirect_count += 1
      end

      return nil unless (200..299).cover?(code)
      decode_html(res.body, res["Content-Type"])

    rescue Net::OpenTimeout, Net::ReadTimeout,
           Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EHOSTUNREACH => e
      Rails.logger.warn("[CompanyInfoExtractor] fetch attempt #{attempts}/#{max_retries} for #{url}: #{e.message}")
      retry if attempts < max_retries
      nil
    rescue URI::InvalidURIError, SocketError => e
      Rails.logger.warn("[CompanyInfoExtractor] URL error for #{url}: #{e.message}")
      nil
    rescue => e
      Rails.logger.warn("[CompanyInfoExtractor] fetch error for #{url}: #{e.message}")
      nil
    end
  end

  # レスポンスボディをUTF-8に変換
  def self.decode_html(body, content_type = nil)
    return "" if body.nil?

    # 1) Content-Type ヘッダから charset を推定
    charset = content_type.to_s[/charset=["']?([^\s;"']+)/i, 1]

    # 2) HTML meta タグから charset を推定（ASCII-8BIT で先頭 4KB を走査）
    if charset.nil?
      head = body.b[0, 4096]
      charset = head[/charset=["']?([A-Za-z0-9\-_]+)/i, 1]
    end

    encoding = case charset&.downcase
               when /utf-?8/                          then "UTF-8"
               when /shift.?jis|sjis|windows-31j|cp932/ then "Shift_JIS"
               when /euc.?jp/                          then "EUC-JP"
               else nil
               end

    if encoding
      body.dup.force_encoding(encoding).encode("UTF-8", invalid: :replace, undef: :replace)
    else
      # 自動判定: UTF-8 → Shift_JIS → EUC-JP の順で試みる
      %w[UTF-8 Shift_JIS EUC-JP].each do |enc|
        begin
          converted = body.dup.force_encoding(enc).encode("UTF-8", invalid: :replace, undef: :replace)
          return converted if converted.valid_encoding?
        rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
          next
        end
      end
      body.encode("UTF-8", invalid: :replace, undef: :replace)
    end
  end

  def self.fetch_rendered_html(url, timeout: 12)
    require "selenium-webdriver"

    options = Selenium::WebDriver::Chrome::Options.new
    # 本番環境の Chrome バイナリのパスを明示的に指定
    options.binary = "/usr/bin/google-chrome"
    options.add_argument("--headless=new")
    options.add_argument("--disable-gpu")
    options.add_argument("--no-sandbox")
    options.add_argument("--disable-dev-shm-usage")
    options.add_argument("--window-size=1280,1000")
    options.add_argument("--ignore-certificate-errors")
    options.add_argument("--disable-blink-features=AutomationControlled")
    options.add_argument("--user-agent=#{USER_AGENT}")

    driver = Selenium::WebDriver.for(:chrome, options: options)
    driver.manage.timeouts.implicit_wait = 0
    driver.manage.timeouts.page_load = timeout
    driver.navigate.to(url)

    wait = Selenium::WebDriver::Wait.new(timeout: timeout)
    begin
      wait.until { driver.execute_script("return document.readyState") == "complete" }
    rescue Selenium::WebDriver::Error::TimeoutError
      nil
    end
    begin
      wait.until do
        driver.find_element(tag_name: "body").text.to_s.strip.length >= 50
      rescue Selenium::WebDriver::Error::NoSuchElementError
        false
      end
    rescue Selenium::WebDriver::Error::TimeoutError
      nil
    end

    driver.page_source
  rescue => e
    Rails.logger.warn("[CompanyInfoExtractor] rendered fetch error for #{url}: #{e.message}")
    nil
  ensure
    driver&.quit rescue nil
  end

  # --- 以下、抽出メソッド ---

  def extract_company
    from_profile || from_footer || from_regex || @customer&.company
  end

  def from_profile
    @doc.css("table tr, dl").each do |row|
      cells = row.css("td, th, dt, dd")
      cells.each_with_index do |cell, i|
        label = cell.text.to_s.gsub(/\s+/, "")
        next unless label.match?(/\A(?:会社名|社名|商号)\z/)

        company = clean_company_name(cells[i + 1]&.text)
        return company if company
      end
    end

    match = @doc.text.to_s.gsub(/\s+/, " ").match(/(?:会社名|社名|商号)\s*[:：]?\s*([^。|｜\n\r]{1,80})/)
    clean_company_name(match[1]) if match
  end

  def from_footer
    footer = @doc.at("footer")
    return if footer.nil?

    clean_company_name(footer.text[/会社名[:：]?\s*([^。|｜\n\r]{1,80})/, 1])
  end

  def from_regex
    sources = [
      @doc.at("title")&.text,
      *@doc.css("h1, h2").first(5).map(&:text),
      @doc.text
    ]

    sources.each do |source|
      company = extract_company_name_from_text(source)
      return company if company
    end

    nil
  end

  def extract_company_name_from_text(text)
    text.to_s.split(/[|｜\n\r\t]/).each do |part|
      match = part.match(LEGAL_ENTITY_NAME_REGEX)
      company = clean_company_name(match[0]) if match
      return company if company
    end

    match = text.to_s.match(LEGAL_ENTITY_NAME_REGEX)
    clean_company_name(match[0]) if match
  end

  def clean_company_name(text)
    value = text.to_s.tr(" ", " ").gsub(/\s+/, " ").strip
    return nil if value.blank?

    value = value.sub(/\A.*の((?:株式会社|有限会社|合同会社|一般社団法人|一般財団法人).*)\z/, "\\1")
                 .sub(/[（(].*\z/, "")
                 .sub(/[【\[].*\z/, "")
                 .sub(/[】\]].*\z/, "")
                 .sub(/[|｜:：／\/].*\z/, "")
                 .sub(/(?:求人|採用|配達|配送|転職|企業情報|会社概要).*\z/, "")
                 .sub(/\s+(?:埋立|造成|一般建設|土木工事|工事|販売|サービス|未経験|歓迎).*\z/, "")
                 .strip

    value.match?(/株式会社|有限会社|合同会社|一般社団法人|一般財団法人/) ? value : nil
  end

  def extract_tel
    branch_tel = extract_tel_from_branch_context
    return branch_tel if branch_tel

    # 優先1: 会社概要テーブル / DL 内の TEL・電話ラベル
    tel = from_table_label_tel(%w[TEL Tel tel 電話 電話番号])
    return tel if tel

    # 優先2: <a href="tel:"> リンク
    # href に複数番号が連結されている場合があるため match で最初の1件のみ採用
    @doc.css("a[href^='tel:']").each do |a|
      raw = a["href"].sub(/^tel:/, "").gsub(/[^\d\-+]/, "")
      m = normalize_tel_text(raw).match(TEL_REGEX)
      return m[0] if m

      formatted = format_plain_tel(raw)
      return formatted if formatted
    end

    # 優先3: footer のテキスト（match で最初の1件のみ）
    if (footer = @doc.at("footer"))
      m = normalize_tel_text(footer.text).match(TEL_REGEX)
      return m[0] if m
    end

    # フォールバック: 全文検索（match で最初の1件のみ）
    m = normalize_tel_text(@doc.text).match(TEL_REGEX)
    m ? m[0] : nil
  end

  # テーブル・DL 内でラベル横のセルから電話番号を探す
  # セル内に複数番号が連結されている場合は最初の1件のみ採用
  def from_table_label_tel(labels)
    @doc.css("table tr, dl").each do |row|
      cells = row.css("td, th, dt, dd")
      cells.each_with_index do |cell, i|
        next unless labels.any? { |l| cell.text.strip.start_with?(l) }
        next_cell = cells[i + 1]
        next unless next_cell
        # scan で全候補を取得し、最初の1件だけ返す（連結防止）
        matches = normalize_tel_text(next_cell.text).scan(TEL_REGEX)
        return matches.first if matches.any?
      end
    end
    nil
  end

  def normalize_tel_text(text)
    text.to_s.tr("０-９", "0-9")
        .gsub(/[‐‑‒–—―−－ーｰ₋]/, "-")
        .gsub(/[（(]\s*(0\d{1,4})\s*[）)]\s*/, '\1-')
  end

  def format_plain_tel(text)
    digits = text.to_s.gsub(/\D/, "")
    return nil if digits.blank?

    case digits.length
    when 11
      if (match = digits.match(/\A(0800)(\d{3})(\d{4})\z/))
        return "#{match[1]}-#{match[2]}-#{match[3]}"
      end
      if (match = digits.match(/\A(050|070|080|090)(\d{4})(\d{4})\z/))
        return "#{match[1]}-#{match[2]}-#{match[3]}"
      end
    when 10
      if (match = digits.match(/\A(0120|0800)(\d{3})(\d{3})\z/))
        return "#{match[1]}-#{match[2]}-#{match[3]}"
      end
      if (match = digits.match(/\A(03|06)(\d{4})(\d{4})\z/))
        return "#{match[1]}-#{match[2]}-#{match[3]}"
      end
      if (match = digits.match(/\A(0\d{2})(\d{3})(\d{4})\z/))
        return "#{match[1]}-#{match[2]}-#{match[3]}"
      end
    end

    nil
  end

  def extract_address
    branch_address = extract_address_from_branch_context
    return branch_address if branch_address

    # 優先1: <address> タグ
    if (addr_tag = @doc.at("address"))
      addr = first_valid_address_match(addr_tag.text)
      return addr if addr
    end

    # 優先2: 会社概要テーブル / DL 内の住所ラベル
    addr = from_table_label_address(%w[住所 所在地 本社住所 本社所在地 配達拠点 配送拠点 営業拠点 拠点])
    return addr if addr

    addr = from_labeled_text_address
    return addr if addr

    # 優先3: footer のテキスト
    if (footer = @doc.at("footer"))
      addr = first_valid_address_match(footer.text)
      return addr if addr
    end

    # フォールバック: 全文検索
    first_valid_address_match(@doc.text)
  end

  # テーブル・DL 内でラベル横のセルから住所を探す
  def from_table_label_address(labels)
    @doc.css("table tr, dl").each do |row|
      cells = row.css("td, th, dt, dd")
      cells.each_with_index do |cell, i|
        next unless labels.any? { |l| cell.text.strip.start_with?(l) }
        next_cell = cells[i + 1]
        next unless next_cell
        text = next_cell.text.gsub(/\s+/, " ")
        m = text.match(ADDRESS_REGEX)
        address = clean_address(m[0]) if m
        return address if address

        inferred = with_customer_prefecture(text)
        m = inferred.match(ADDRESS_REGEX)
        address = clean_address(m[0]) if m
        return address if address
      end
    end
    nil
  end

  def from_labeled_text_address
    text = @doc.text.gsub(/\s+/, " ")
    label_pattern = /(?:本社所在地|本社住所|所在地|住所|本社|配達拠点|配送拠点|営業拠点|拠点)/
    patterns = [
      /#{label_pattern}\s*[：:]?\s*(?:〒?\s*\d{3}[-－ー]?\d{4}\s*)?([^。|｜\n\r]{0,20}#{PREF_PATTERN}[^\n\r<>]{5,180})/,
      /#{label_pattern}[\s\S]{0,40}(#{PREF_PATTERN}[^\n\r<>]{5,180})/
    ]

    patterns.each do |pattern|
      match = text.match(pattern)
      next unless match

      address = clean_address(match[1])
      return address if address
    end

    inferred = text.match(/#{label_pattern}\s*[：:]?\s*〒?\s*\d{3}[-－ー]?\d{4}\s*([^。|｜\n\r]{5,120})/)
    if inferred
      address = clean_address(with_customer_prefecture(inferred[1]))
      return address if address
    end

    nil
  end

  def first_valid_address_match(text)
    text.to_s.gsub(/\s+/, " ").scan(ADDRESS_REGEX).each do |candidate|
      address = clean_address(candidate)
      return address if address
    end

    nil
  end

  def with_customer_prefecture(text)
    value = text.to_s.strip.sub(/\A〒?\s*\d{3}-?\d{4}\s*/, "")
    return value if value.match?(PREF_PATTERN)

    pref = @customer&.address.to_s[PREF_PATTERN]
    pref.present? ? "#{pref}#{value}" : value
  end

  # 住所文字列から TEL/FAX/営業時間 等の後続テキストを除去する
  # 例: "埼玉県 幸手市 千塚398-5 TEL：0480-43-8771..." → "埼玉県 幸手市 千塚398-5"
  def clean_address(text)
    return nil if text.blank?
    s = text.dup
    s = s.tr("\u00A0", " ")
         .gsub(/[\u200B\u200C\u200D\uFEFF]/, "")
    s = s.split(/Google\s*Map|GOOGLE\s*Map|Google\s*map|GOOGLE\s*MAP|\bMAP\b/i, 2).first.to_s

    # 以下のキーワードより後ろは切り捨てる（先頭側が住所本体）
    stop_pattern = /
      (?:TEL|Tel|tel|ＴＥＬ|℡|電話|FAX|Fax|fax|ＦＡＸ|
         営業時間|営業日|定休日?|受付時間|受付|
         E[-\s]?mail|Email|e-?mail|メール(?:アドレス)?|Mail|
         URL|ＵＲＬ|ホームページ|HP|
         アクセス|最寄り?駅|地図|Google\s*(?:MAP|Map|map)|GoogleMapで見る|Googleマップ|MAPを見る|MAP|map|
         代表者|(?<!本社)代表|設立|資本金|従業員|業務内容|事業内容|事業案内|施工計画|会社情報|
         代表挨拶|経営理念|行動指針|拠点一覧|地域社会への貢献|沿革|ホーム|会社紹介|
         役員|取締役|営業本部|店[\s ]*舗|店舗|
         サイトマップ|個人情報保護方針|購入ページ|TOP|Go\s*to\s*top|keyboard_arrow_right|事業一覧|
         荷物積み込み場|稼働期間|現場風景|週休|勤務時間|時間\s*[0-9０-９]|
         ※\s*本社所在地|
         昭和\s*\d+\s*年|平成\s*\d+\s*年|令和\s*\d+\s*年|
         求人|採用|お問い合わせ|お問合せ|問合せ|CONTACT|Contact|contact|READ\s*MORE)
         |Copyright|All\s+Rights\s+Reserved
    /x
    s = s.split(stop_pattern, 2).first.to_s
    s = s.split(/(?:有料職業紹介事業|WEB広告事業|デジタルサイネージ事業|©)/, 2).first.to_s
    s = s.split(/(?:potentialAction|urlTemplate|@type|","|"\s*[:,])/, 2).first.to_s
    s = s.split(/[【［\[]\s*(?:本社代表|代表|TEL|Tel|tel|電話)/, 2).first.to_s
    s = s.split(/[A-Za-z0-9._%+\-]+_at_[A-Za-z0-9._%+\-]+/, 2).first.to_s
    s = s.split(/[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}/, 2).first.to_s
    s = s.split(/0[0-9０-９]{1,4}[‐‑‒–—―−－ーｰ₋-][0-9０-９]{1,4}[‐‑‒–—―−－ーｰ₋-][0-9０-９]{3,4}/, 2).first.to_s
    s = s.split(/[・、,]\s*(?:本社|本店|法人営業部|[一-龥ァ-ヶA-Za-z]{1,12}(?:本社|本店|支店|営業所|出張所|オフィス|事業所|工場|倉庫|センター))\s*〒\s*\d{3}-?\d{4}/, 2).first.to_s
    s = s.split(/(?<=[0-9０-９号番地])\s*(?:本社|本店|法人営業部|[一-龥ァ-ヶA-Za-z]{1,12}(?:本社|本店|支店|営業所|出張所|オフィス|事業所|工場|倉庫|センター))\s*〒\s*\d{3}-?\d{4}/, 2).first.to_s
    s = s.split(/\s+(?:事業所|支店|営業所|出張所|オフィス|工場|倉庫|センター)[：:][\s ]*〒\s*\d{3}-?\d{4}/, 2).first.to_s
    s = s.split(/\s+[一-龥ァ-ヶA-Za-z]{1,12}(?:支店|営業所|出張所|オフィス|事業所|工場|倉庫|センター)[：:][\s ]*〒\s*\d{3}-?\d{4}/, 2).first.to_s
    s = s.split(/\s+(?:本社|第二工場|支店|営業所|工場|倉庫|センター)?\s*〒\s*\d{3}-?\d{4}/, 2).first.to_s
    s = s.split(/[\s ]*[［\[][\s ]*[一-龥ァ-ヶA-Za-z]{0,12}(?:本社|支店|営業所|出張所|オフィス|事業所|工場|倉庫|センター|車庫)[\s ]*[］\]][\s ]*〒?[\s ]*\d{3}[-－ー]?\d{4}/, 2).first.to_s
    s = s.split(/[［\[]\s*[一-龥ァ-ヶA-Za-z]{1,12}(?:支店|営業所|出張所|オフィス|事業所|工場|倉庫|センター)\s*[］\]]\s*(?=#{PREF_PATTERN})/, 2).first.to_s
    s = s.split(/[／\/][\s ]*(?:工場|支店|営業所|出張所|オフィス|事業所|倉庫|センター)[\s ]*(?=#{PREF_PATTERN})/, 2).first.to_s
    s = s.split(/\s+[一-龥ァ-ヶA-Za-z]{1,12}(?:本社|支店|営業所|出張所|オフィス|事業所|工場|倉庫|センター)[：:][\s ]*(?=#{PREF_PATTERN})/, 2).first.to_s
    s = s.split(/\s+\S{1,12}(?:支店|営業所|出張所|オフィス|事業所|工場|倉庫|センター)\s*(?=#{PREF_PATTERN})/, 2).first.to_s
    s = s.split(/(?<=[0-9０-９号番地])\s*[一-龥ァ-ヶA-Za-z]{1,12}(?:本社|支社|支店|営業所|出張所|オフィス|事務所|事業所|工場|倉庫|センター)\s+[一-龥ァ-ヶ]{1,12}(?:市|区|町|村)/, 2).first.to_s

    # 連続する空白・全角空白・特殊記号を1つに圧縮
    s = s.gsub(/[\t\r\n]+/, " ").gsub(/[  ]{2,}/, " ")
    if s.scan(PREF_PATTERN).size > 1
      first_address = s.match(/\A(#{PREF_PATTERN}.+?)(?=#{PREF_PATTERN})/)
      s = first_address[1] if first_address
    end
    s = s.sub(/\A(#{PREF_PATTERN})\s*〒?\s*\d{3}[-－ー]?\d{4}\s*/, "\\1")
    s = s.sub(/\A(#{PREF_PATTERN})[  ]+/, "\\1")
    s = s.sub(/[\s ]*[［\[][\s ]*[一-龥ァ-ヶA-Za-z]{0,12}(?:本社|支店|営業所|出張所|オフィス|事業所|工場|倉庫|センター|車庫)[\s ]*[］\]](?:[\s ]*〒?[\s ]*\d{3}[-－ー]?\d{4})\z/, "")
    s = s.sub(/[（(]\s*→?\s*MAPを見る\s*[）)]?\z/i, "")
    s = s.sub(/[（(]\s*→?\s*\z/, "")
    # 末尾の区切り記号・空白を除去
    s = s.sub(/[\s 、。,.:：;；\-－ー｜|／\/■□◆◇●○◎※＊*]+\z/, "")
    s = s.sub(/[（(]\z/, "")
    s = s.sub(/[【［\[]\z/, "")
    s = s.sub(/[  ]*[＜<]\s*[一-龥ァ-ヶA-Za-z]{0,12}(?:本社|支社|支店|営業所|出張所|オフィス|事業所|工場|倉庫|センター)\s*[＞>]\s*[・、,]*\z/, "")
    s = s.sub(/[  ]*(?:建[  ]*築|土木|内装|配送|運送業?|軽貨物.*|物流.*)\z/, "")
    s = s.sub(/\s+(?:本社|支社|支店|営業所|出張所|オフィス|事務所|事業所|工場|倉庫|センター)\z/, "")
    s = s.sub(/\s+\S{1,12}(?:支社|支店|営業所|出張所|オフィス|事務所|事業所|工場|倉庫|センター)\z/, "")
    s = s.strip.presence
    return nil if s.nil?

    # 住所として妥当か検証する。妥当でなければ nil を返す。
    valid_address?(s) ? s : nil
  end

  # 住所として妥当か検証する。
  # NG 例:
  #   - "大阪府のWebマーケティ."        ← 都道府県の直後に助詞「の」（文章の一部）
  #   - "富山県、石川県において、…"     ← 文章中の地名列挙
  #   - "東京都"                       ← 市区町村以下が無い
  # OK 例:
  #   - "埼玉県 幸手市 千塚398-5"
  #   - "東京都新宿区西新宿1-1-1"
  def valid_address?(text)
    return false if text.blank?

    # 1. 都道府県名で始まること
    pref_match = text.match(/\A(?:北海道|青森県|岩手県|宮城県|秋田県|山形県|福島県|茨城県|栃木県|群馬県|埼玉県|千葉県|東京都|神奈川県|新潟県|富山県|石川県|福井県|山梨県|長野県|岐阜県|静岡県|愛知県|三重県|滋賀県|京都府|大阪府|兵庫県|奈良県|和歌山県|鳥取県|島根県|岡山県|広島県|山口県|徳島県|香川県|愛媛県|高知県|福岡県|佐賀県|長崎県|熊本県|大分県|宮崎県|鹿児島県|沖縄県)/)
    return false if pref_match.nil?

    after_pref = text[pref_match.end(0)..]

    # 2. 都道府県名の直後に助詞・読点が続く場合は文章の一部 → 除外
    return false if after_pref.match?(/\A(?:の|や|や、|において|では|から|へ|を|が|は|も|と|下|、|，|・|及び|および)/)

    # 3. 市区町村（市/区/町/村/郡）が含まれていること
    return false unless after_pref.match?(/(?:市|区|町|村|郡)/)
    return false unless text.match?(/[0-9０-９]|丁目|番地|番|号|[-－ー]/)
    return false if text.scan(PREF_PATTERN).size > 1

    true
  end

  def extract_tel_from_branch_context
    branch_contexts.each do |context|
      m = normalize_tel_text(context).match(TEL_REGEX)
      return m[0] if m
    end
    nil
  end

  def extract_address_from_branch_context
    branch_contexts.each do |context|
      m = context.match(ADDRESS_REGEX)
      address = clean_address(m[0]) if m
      return address if address
    end
    nil
  end

  def branch_contexts
    token_sources = branch_context_tokens
    return [] if token_sources.empty?

    text = @doc.text.to_s.gsub(/\s+/, " ")
    compact_text = text.gsub(/\s+/, "")
    pref = @customer&.address.to_s[PREF_PATTERN]

    token_sources.filter_map do |token, source|
      compact_index = compact_text.index(token)
      next if compact_index.nil?

      start_index = compact_index
      if source == :address && pref.present?
        pref_index = compact_text.rindex(pref, compact_index)
        start_index = pref_index if pref_index && compact_index - pref_index <= 30
      end

      compact_text[start_index, 700]
    end.uniq
  end

  def branch_context_tokens
    branch_tokens = @customer&.company.to_s.scan(BRANCH_TOKEN_REGEX).map { |token| token.gsub(/\s+/, "") }
    @customer&.company.to_s.split(/[\s ／\/・,、()（）\[\]「」【】]+/).each do |part|
      normalized = part.gsub(/\s+/, "")
      next if normalized.length < 3
      next unless normalized.match?(/センター|キッチン|オフィス|本社|営業所|支店|倉庫|工場|事業所|配送|カーゴ|施設|店舗|会館|支部|出張所/)
      next if normalized.match?(/\A(?:ドライバ|ドライバー|求人|採用|募集|スタッフ|アルバイト|パート|正社員)\z/)

      branch_tokens << normalized
      place_prefix = normalized.match(/\A(.{2,8}?)(?:配送センター|デリバリーステーション|センター|営業所|支店|倉庫|工場|事業所|店舗|施設)\z/)
      branch_tokens << place_prefix[1] if place_prefix && place_prefix[1].length >= 2
    end
    branch_tokens.uniq!
    return [] if branch_tokens.empty?

    address_tokens = @customer&.address.to_s.scan(/[^\s ,、。〒]{1,12}(?:市|区|町|村)/).map { |token| token.gsub(/\s+/, "") }
    (branch_tokens.map { |token| [token, :company] } + address_tokens.map { |token| [token, :address] }).uniq
  end

  def extract_contact_url
    @doc.css("a").each do |a|
      href = a["href"].to_s.strip
      text = a.text.to_s.strip
      next if href.blank?
      next if href.match?(NON_CONTACT_LINK_PATH) || text.match?(NON_CONTACT_LINK_TEXT)
      return href if href.match?(CONTACT_LINK_PATH) || text.match?(CONTACT_LINK_TEXT)
    end
    nil
  end
end