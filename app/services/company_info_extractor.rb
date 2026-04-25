# frozen_string_literal: true

require "nokogiri"
require "net/http"
require "uri"
require "openssl"

class CompanyInfoExtractor
  TEL_REGEX = /0\d{1,4}-\d{1,4}-\d{3,4}/

  PREF_PATTERN = /(?:北海道|青森県|岩手県|宮城県|秋田県|山形県|福島県|茨城県|栃木県|群馬県|
                    埼玉県|千葉県|東京都|神奈川県|新潟県|富山県|石川県|福井県|山梨県|長野県|
                    岐阜県|静岡県|愛知県|三重県|滋賀県|京都府|大阪府|兵庫県|奈良県|和歌山県|
                    鳥取県|島根県|岡山県|広島県|山口県|徳島県|香川県|愛媛県|高知県|福岡県|
                    佐賀県|長崎県|熊本県|大分県|宮崎県|鹿児島県|沖縄県)/x

  ADDRESS_REGEX = /(?:北海道|青森県|岩手県|宮城県|秋田県|山形県|福島県|茨城県|栃木県|群馬県|埼玉県|千葉県|東京都|神奈川県|新潟県|富山県|石川県|福井県|山梨県|長野県|岐阜県|静岡県|愛知県|三重県|滋賀県|京都府|大阪府|兵庫県|奈良県|和歌山県|鳥取県|島根県|岡山県|広島県|山口県|徳島県|香川県|愛媛県|高知県|福岡県|佐賀県|長崎県|熊本県|大分県|宮崎県|鹿児島県|沖縄県)[^\n\r<>「」【】]{5,80}/

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

  # --- 以下、抽出メソッド ---

  def extract_company
    from_profile || from_footer || from_regex || @customer&.company
  end

  def from_profile
    @doc.text[/会社名[:：]?\s*(.+)/, 1]&.strip
  end

  def from_footer
    footer = @doc.at("footer")
    return if footer.nil?
    footer.text[/会社名[:：]?\s*(.+)/, 1]&.strip
  end

  def from_regex
    @doc.text[/(株式会社|有限会社|合同会社).+?/]
  end

  def extract_tel
    # 優先1: <a href="tel:"> リンク（最も信頼性が高い）
    # href に複数番号が連結されている場合があるため match で最初の1件のみ採用
    @doc.css("a[href^='tel:']").each do |a|
      raw = a["href"].sub(/^tel:/, "").gsub(/[^\d\-+]/, "")
      m = raw.match(TEL_REGEX)
      return m[0] if m
    end

    # 優先2: 会社概要テーブル / DL 内の TEL・電話ラベル
    tel = from_table_label_tel(%w[TEL Tel tel 電話 電話番号])
    return tel if tel

    # 優先3: footer のテキスト（match で最初の1件のみ）
    if (footer = @doc.at("footer"))
      m = footer.text.match(TEL_REGEX)
      return m[0] if m
    end

    # フォールバック: 全文検索（match で最初の1件のみ）
    m = @doc.text.match(TEL_REGEX)
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
        matches = next_cell.text.scan(TEL_REGEX)
        return matches.first if matches.any?
      end
    end
    nil
  end

  def extract_address
    # 優先1: <address> タグ
    if (addr_tag = @doc.at("address"))
      m = addr_tag.text.match(ADDRESS_REGEX)
      return clean_address(m[0]) if m
    end

    # 優先2: 会社概要テーブル / DL 内の住所ラベル
    addr = from_table_label_address(%w[住所 所在地 本社住所 本社所在地])
    return addr if addr

    # 優先3: footer のテキスト
    if (footer = @doc.at("footer"))
      m = footer.text.match(ADDRESS_REGEX)
      return clean_address(m[0]) if m
    end

    # フォールバック: 全文検索
    m = @doc.text.match(ADDRESS_REGEX)
    m ? clean_address(m[0]) : nil
  end

  # テーブル・DL 内でラベル横のセルから住所を探す
  def from_table_label_address(labels)
    @doc.css("table tr, dl").each do |row|
      cells = row.css("td, th, dt, dd")
      cells.each_with_index do |cell, i|
        next unless labels.any? { |l| cell.text.strip.start_with?(l) }
        next_cell = cells[i + 1]
        next unless next_cell
        m = next_cell.text.match(ADDRESS_REGEX)
        return clean_address(m[0]) if m
      end
    end
    nil
  end

  # 住所文字列から TEL/FAX/営業時間 等の後続テキストを除去する
  # 例: "埼玉県 幸手市 千塚398-5 TEL：0480-43-8771..." → "埼玉県 幸手市 千塚398-5"
  def clean_address(text)
    return nil if text.blank?
    s = text.dup

    # 以下のキーワードより後ろは切り捨てる（先頭側が住所本体）
    stop_pattern = /
      (?:TEL|Tel|tel|ＴＥＬ|℡|電話|FAX|Fax|fax|ＦＡＸ|
         営業時間|営業日|定休日?|受付時間|受付|
         E[-\s]?mail|Email|e-?mail|メール(?:アドレス)?|Mail|
         URL|ＵＲＬ|ホームページ|HP|
         アクセス|最寄り?駅|地図|
         代表者|設立|資本金|従業員|業務内容)
    /x
    s = s.split(stop_pattern, 2).first.to_s

    # 連続する空白・全角空白・特殊記号を1つに圧縮
    s = s.gsub(/[\t\r\n]+/, " ").gsub(/[ 　]{2,}/, " ")
    # 末尾の区切り記号・空白を除去
    s = s.sub(/[\s　、。,.:：;；\-－ー｜|／\/]+\z/, "")
    s.strip.presence
  end

  def extract_contact_url
    @doc.css("a").each do |a|
      href = a["href"]
      next if href.blank?
      return href if href.match?(/contact|お問い合わせ|問合せ/)
    end
    nil
  end
end
