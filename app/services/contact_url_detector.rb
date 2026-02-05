# frozen_string_literal: true

require 'selenium-webdriver'
require 'webdrivers'
require 'uri'
require 'net/http'
require 'set'

class ContactUrlDetector
  # リンクテキスト・alt に含まれるキーワード（スコアリング用）
  LINK_KEYWORDS = %w[
    お問い合わせ 問い合わせ contact inquiry 資料請求
    お問合せ 問合せ お問合わせ
  ].freeze

  # URLパスに含まれるキーワード（スコアリング用）
  PATH_KEYWORDS = %w[
    contact inquiry form toiawase otoiawase
    inquire mailform mail_form formmail
  ].freeze

  # 除外キーワード（リンクテキスト or URL に含まれていたらスキップ）
  EXCLUDE_KEYWORDS = %w[
    recruit 採用 求人 login cart faq privacy
    career 会社概要 about sitemap blog news
    個人情報 プライバシー ログイン
  ].freeze

  # よくあるお問い合わせページパス（ステップ3で試行）
  COMMON_PATHS = %w[
    /contact
    /contact/
    /inquiry
    /inquiry/
    /contact.html
    /inquiry.html
    /form
    /form/
    /toiawase
    /toiawase/
    /otoiawase
    /otoiawase/
    /contactus
    /contact-us
    /contact_us
  ].freeze

  # 404判定用キーワード
  NOT_FOUND_PATTERNS = %w[
    404 not\ found ページが見つかりません お探しのページ
    page\ not\ found ページは存在しません
  ].freeze

  # お問い合わせ関連ページ判定キーワード（フォームがなくてもOK）
  CONTACT_PAGE_KEYWORDS = %w[
    お問い合わせ 問い合わせ contact inquiry
    お問合せ お問合わせ ご相談 資料請求
  ].freeze

  # ページ読み込み待機秒数
  PAGE_LOAD_WAIT = 2

  def initialize(debug: false, headless: true)
    @debug = debug
    @headless = headless
    @driver = nil
    @checked_urls = Set.new  # 既にチェック済みのURL（重複アクセス防止）
  end

  # メインの検出メソッド
  # @param customer [Customer] url が設定された顧客レコード
  # @return [Hash] { status: 'detected'|'not_detected', contact_url: URL, message: String }
  def detect(customer)
    return { status: 'not_detected', contact_url: nil, message: 'URLが設定されていません' } if customer.url.blank?

    base_url = normalize_url(customer.url)
    @checked_urls = Set.new  # 顧客ごとにリセット
    log "=== ContactUrlDetector: #{customer.company} (#{base_url}) ==="

    # 入力URL自体がNGブラックリストに該当する場合はスキップ
    if blocked_url?(base_url)
      log "  → NGブラックリスト該当（入力URL）: #{base_url}"
      return { status: 'not_detected', contact_url: nil, message: "NGブラックリスト該当: #{base_url}" }
    end

    begin
      setup_driver

      # ステップ1: HP自体にフォームがあるか確認
      log "ステップ1: トップページのフォーム確認"
      result = check_page_for_form(base_url)
      if result
        if blocked_url?(result)
          log "  → NGブラックリスト該当（検出URL）: #{result}"
        else
          log "  → トップページにフォーム検出: #{result}"
          return { status: 'detected', contact_url: result, message: 'トップページにフォームを検出' }
        end
      end

      # ステップ2: ページ内リンクを探索
      log "ステップ2: リンク探索"
      result = explore_links(base_url)
      if result
        if blocked_url?(result)
          log "  → NGブラックリスト該当（検出URL）: #{result}"
        else
          log "  → リンク先にフォーム/お問い合わせページ検出: #{result}"
          return { status: 'detected', contact_url: result, message: 'リンク先にフォームを検出' }
        end
      end

      # ステップ3: 一般的なパスを試行（404は事前スキップ）
      log "ステップ3: 一般パス試行"
      result = try_common_paths(base_url)
      if result
        if blocked_url?(result)
          log "  → NGブラックリスト該当（検出URL）: #{result}"
        else
          log "  → 一般パスにフォーム検出: #{result}"
          return { status: 'detected', contact_url: result, message: '一般パスにフォームを検出' }
        end
      end

      log "  → フォーム未検出"
      { status: 'not_detected', contact_url: nil, message: '3段階の検出すべてで該当フォームが見つかりませんでした' }
    rescue StandardError => e
      log "エラー: #{e.message}"
      { status: 'not_detected', contact_url: nil, message: "検出中にエラー: #{e.message}" }
    ensure
      teardown_driver
    end
  end

  private

  # ============================================================
  # ブラウザ管理
  # ============================================================

  def setup_driver
    options = Selenium::WebDriver::Chrome::Options.new
    options.add_argument('--headless') if @headless
    options.add_argument('--disable-gpu')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--window-size=1280,800')
    options.add_argument('--ignore-certificate-errors')

    @driver = Selenium::WebDriver.for(:chrome, options: options)
    @driver.manage.timeouts.implicit_wait = 3
    @driver.manage.timeouts.page_load = 10
  end

  def teardown_driver
    @driver&.quit
    @driver = nil
  end

  def driver
    @driver
  end

  # ============================================================
  # ステップ1: ページ自体にフォームがあるか確認
  # ============================================================

  def check_page_for_form(url)
    normalized = normalize_check_url(url)
    return nil if @checked_urls.include?(normalized)
    @checked_urls << normalized

    navigate_safely(url) or return nil
    return nil if page_is_404?
    has_contact_form? ? current_url : nil
  end

  # フォームまたはお問い合わせ関連ページをチェック（ステップ2用）
  def check_page_for_form_or_contact(url)
    normalized = normalize_check_url(url)
    return nil if @checked_urls.include?(normalized)
    @checked_urls << normalized

    navigate_safely(url) or return nil
    return nil if page_is_404?

    # まずフォームがあるか確認
    return current_url if has_contact_form?

    # フォームがなくても、お問い合わせ関連ページならOK
    return current_url if contact_related_page?

    nil
  end

  # ============================================================
  # ステップ2: ページ内リンクをキーワードスコアリングで探索
  # ============================================================

  def explore_links(base_url)
    # トップページに戻る（ステップ1で別ページに遷移している可能性）
    navigate_safely(base_url)

    # 現在のページからリンクを収集してスコアリング
    links = collect_scored_links(base_url)
    log "  スコア付きリンク: #{links.size}件"

    # 上位5件をチェック（フォーム or お問い合わせページ）
    links.first(5).each do |link_info|
      log "  チェック中: #{link_info[:url]} (score=#{link_info[:score]}, text=#{link_info[:text]})"
      result = check_page_for_form_or_contact(link_info[:url])
      return result if result
    end

    nil
  end

  def collect_scored_links(base_url)
    base_uri = URI.parse(base_url) rescue nil
    return [] unless base_uri

    scored = []

    begin
      anchors = driver.find_elements(:tag_name, 'a')
      anchors.each do |a|
        href = a.attribute('href').to_s.strip
        next if href.empty? || href.start_with?('javascript:', 'mailto:', 'tel:', '#')

        # 絶対URLに変換
        full_url = resolve_url(base_url, href)
        next unless full_url

        # 同一ドメインのみ対象
        link_uri = URI.parse(full_url) rescue nil
        next unless link_uri && link_uri.host == base_uri.host

        # 除外チェック
        text = a.text.to_s.strip
        alt = a.attribute('alt').to_s.strip
        combined = "#{text} #{alt} #{full_url}".downcase
        next if EXCLUDE_KEYWORDS.any? { |kw| combined.include?(kw.downcase) }

        # スコアリング
        score = calculate_link_score(text, alt, full_url)
        next if score <= 0

        scored << { url: full_url, text: text, score: score }
      rescue Selenium::WebDriver::Error::StaleElementReferenceError
        next
      end
    rescue StandardError => e
      log "  リンク収集エラー: #{e.message}"
    end

    # スコア降順、重複URL除去
    scored.uniq { |l| l[:url] }.sort_by { |l| -l[:score] }
  end

  def calculate_link_score(text, alt, url)
    score = 0
    combined_text = "#{text} #{alt}".downcase
    path = URI.parse(url).path.to_s.downcase rescue ''

    # リンクテキストにキーワードがあれば高スコア
    LINK_KEYWORDS.each do |kw|
      score += 10 if combined_text.include?(kw.downcase)
    end

    # URLパスにキーワードがあれば加点
    PATH_KEYWORDS.each do |kw|
      score += 5 if path.include?(kw.downcase)
    end

    score
  end

  # ============================================================
  # ステップ3: よくあるパスを試行（HTTP HEAD で 404 事前スキップ）
  # ============================================================

  def try_common_paths(base_url)
    base_uri = URI.parse(base_url) rescue nil
    return nil unless base_uri

    origin = "#{base_uri.scheme}://#{base_uri.host}"
    origin += ":#{base_uri.port}" unless [80, 443].include?(base_uri.port)

    COMMON_PATHS.each do |path|
      url = "#{origin}#{path}"
      normalized = normalize_check_url(url)
      next if @checked_urls.include?(normalized)

      # HTTP HEAD で存在チェック（404なら即スキップ）
      unless url_exists?(url)
        log "  スキップ(404): #{url}"
        @checked_urls << normalized
        next
      end

      log "  試行: #{url}"
      result = check_page_for_form_or_contact(url)
      return result if result
    end

    nil
  end

  # ============================================================
  # フォーム判定
  # ============================================================

  def has_contact_form?
    # パターン1: form要素内に input 2個以上 + textarea
    forms = driver.find_elements(:tag_name, 'form')
    forms.each do |form|
      inputs = count_visible_inputs(form)
      has_textarea = form.find_elements(:tag_name, 'textarea').any? { |ta| visible?(ta) }

      if inputs >= 2 && has_textarea
        log "    フォーム検出(パターン1): input=#{inputs}, textarea=true"
        return true
      end

      # パターン2: form要素内にinput 3個以上（textarea無しでも可）
      if inputs >= 3
        log "    フォーム検出(パターン2): input=#{inputs}"
        return true
      end
    end

    # パターン3: form要素なし + ページ全体で input 3個以上 + textarea（SPA対応）
    if forms.empty?
      all_inputs = count_visible_inputs_on_page
      all_textarea = driver.find_elements(:tag_name, 'textarea').any? { |ta| visible?(ta) }
      if all_inputs >= 3 && all_textarea
        log "    フォーム検出(パターン3/SPA): input=#{all_inputs}, textarea=true"
        return true
      end
    end

    false
  rescue StandardError => e
    log "    フォーム判定エラー: #{e.message}"
    false
  end

  # お問い合わせ関連ページかどうか判定（フォームがなくてもOK）
  # 条件: ページタイトル or h1 にお問い合わせキーワードが含まれている
  def contact_related_page?
    title = driver.title.to_s.downcase
    body_text = ''
    begin
      # h1, h2 のテキストを取得
      headings = driver.find_elements(:css, 'h1, h2')
      body_text = headings.map { |h| h.text.to_s.strip }.join(' ').downcase
    rescue StandardError
      # 取得できなければ空文字のまま
    end

    combined = "#{title} #{body_text}"
    matched = CONTACT_PAGE_KEYWORDS.any? { |kw| combined.include?(kw.downcase) }
    if matched
      log "    お問い合わせ関連ページ検出: title/heading にキーワード含む"
    end
    matched
  rescue StandardError
    false
  end

  def count_visible_inputs(container)
    inputs = container.find_elements(:tag_name, 'input')
    inputs.count do |input|
      type = input.attribute('type').to_s.downcase
      # hidden, submit, button, image は除外
      !%w[hidden submit button image reset].include?(type) && visible?(input)
    end
  end

  def count_visible_inputs_on_page
    inputs = driver.find_elements(:tag_name, 'input')
    inputs.count do |input|
      type = input.attribute('type').to_s.downcase
      !%w[hidden submit button image reset].include?(type) && visible?(input)
    end
  end

  def visible?(element)
    element.displayed?
  rescue StandardError
    false
  end

  # ============================================================
  # 404検出
  # ============================================================

  # HTTP HEAD リクエストで URL が存在するか事前チェック（ステップ3用）
  def url_exists?(url)
    uri = URI.parse(url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == 'https')
    http.open_timeout = 3
    http.read_timeout = 3
    http.verify_mode = OpenSSL::SSL::VERIFY_NONE

    response = http.request_head(uri.request_uri)
    code = response.code.to_i
    # 200系 or 301/302リダイレクトなら存在
    code >= 200 && code < 400
  rescue StandardError
    # タイムアウト等 → 存在するかもしれないのでtrue（Seleniumで確認）
    true
  end

  # ページ内容が404エラーページかどうか判定
  def page_is_404?
    title = driver.title.to_s.downcase
    NOT_FOUND_PATTERNS.any? { |pattern| title.include?(pattern) }
  rescue StandardError
    false
  end

  # ============================================================
  # ユーティリティ
  # ============================================================

  def navigate_safely(url)
    driver.navigate.to(url)
    sleep PAGE_LOAD_WAIT
    true
  rescue Selenium::WebDriver::Error::TimeoutError
    log "    ページロードタイムアウト: #{url}"
    false
  rescue Selenium::WebDriver::Error::WebDriverError => e
    log "    ナビゲーションエラー: #{e.message}"
    false
  end

  def current_url
    driver.current_url
  rescue StandardError
    nil
  end

  def normalize_url(url)
    url = url.strip
    url = "https://#{url}" unless url.match?(%r{\Ahttps?://}i)
    uri = URI.parse(url)
    uri.path = '/' if uri.path.empty?
    uri.to_s
  rescue URI::InvalidURIError
    "https://#{url}"
  end

  # チェック済みURL比較用の正規化（末尾スラッシュ差異を吸収）
  def normalize_check_url(url)
    url.to_s.chomp('/')
  end

  def resolve_url(base, href)
    URI.join(base, href).to_s
  rescue URI::InvalidURIError, URI::BadURIError
    nil
  end

  # NGブラックリスト判定（URL部分一致）
  def blocked_url?(url)
    return false if url.nil? || url.empty?
    patterns = defined?(BLOCKED_URL_PATTERNS) ? BLOCKED_URL_PATTERNS : []
    patterns.any? { |pattern| url.downcase.include?(pattern.downcase) }
  end

  def log(msg)
    puts "[ContactUrlDetector] #{msg}" if @debug
    Rails.logger.info("[ContactUrlDetector] #{msg}") if defined?(Rails)
  end
end
