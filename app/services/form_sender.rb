# frozen_string_literal: true

require 'selenium-webdriver'
require 'openssl'
require 'net/http'

# SSL対策は config/initializers/ssl_fix.rb に移動済み

class FormSender
  # 送信者情報（固定）
  SENDER_INFO = {
    # 名前（フルネーム・分割両対応）
    name: '山口 俊二',
    name_sei: '山口',
    name_mei: '俊二',
    # フリガナ（カタカナ）
    name_kana: 'ヤマグチ シュンジ',
    name_kana_sei: 'ヤマグチ',
    name_kana_mei: 'シュンジ',
    # ふりがな（ひらがな）
    name_hira: 'やまぐち しゅんじ',
    name_hira_sei: 'やまぐち',
    name_hira_mei: 'しゅんじ',
    # 都道府県
    prefecture: '東京都',
    # メール
    email: 'mail1@ebisu-hotel.tokyo',
    # 電話番号（フル・分割両対応）
    tel: '050-7119-1716',
    tel_no_hyphen: '05071191716',
    tel1: '050',
    tel2: '7119',
    tel3: '1716',
    # 郵便番号（フル・分割両対応）
    zip: '104-0061',
    zip1: '104',
    zip2: '0061',
    # 住所（フル・分割両対応）
    address: '東京都中央区銀座6-13-16',
    address_city: '中央区',
    address_street: '銀座6-13-16',
    company: '', # 後で設定
    message: <<~MESSAGE
      お忙しい中失礼いたします。
      山口でございます。
      本日は、御社に新規商談アポイント開拓のキャンペーンをご提供できればと思い、ご連絡いたしました。
      弊社ではBtoB企業様向けに新規アポイントの獲得代行サービスを提供しており、ITプログラミング技術を活用したマッチング精度の高いリストをもとに架電を行っております。
      この業界最高水準のリストを活用し、これまでに累計40,000件以上のアポイントを獲得してまいりました。
      主なアプローチはテレフォンアポイントとなりますが、企業様のサービス内容に応じて問い合わせフォーム送信や広告出稿など、多彩な手法に対応しております。これにより、質の高いアポイントの最大化を実現いたします。
      現在、弊社ではスタッフ増員に伴いキャンペーンを実施しております。
      【キャンペーン内容】
      ＠導入費用・リスト制作・スクリプト制作【０円】
      ＠契約期間なしの取り切り型
      ＠安心の完全成果報酬対応
      もし少しでもご興味をお持ちいただけましたら、いつでも対応が可能です。
      【商談希望】の旨をお伝えいただければ幸いです。
      ご連絡を心よりお待ちしております。
    MESSAGE
  }.freeze

  # フィールド検出用キーワード（優先度順）
  FIELD_PATTERNS = {
    name: %w[name 名前 お名前 氏名 your-name fullname full_name shimei simei 担当者 ご担当者 担当],
    name_kana: %w[kana カナ かな フリガナ ふりがな furigana name_kana kna],
    email: %w[email mail メール e-mail your-email メールアドレス eml m_address],
    email_confirm: %w[email_confirm mail_confirm 確認用 confirm re-email eml2],
    tel: %w[tel phone 電話 携帯 telephone your-tel denwa],
    zip: %w[zip postal 郵便 〒 yubin post-code zipcode postcode],
    prefecture: %w[prefecture pref 都道府県 todoufuken todofuken ken],
    company: %w[company 会社 御社 貴社 organization 社名 company_name kaisya comname 御社名 会社名 corpname corp 法人],
    address: %w[address 住所 所在地 your-address jusho adr add],
    message: %w[message body 内容 お問い合わせ内容 inquiry comment お問い合わせ 備考 remarks naiyo toi その他 content contents ques]
  }.freeze

  # 送信ボタン検出用キーワード
  SUBMIT_PATTERNS = %w[送信 確認 submit send 入力内容を確認 送信する 確認する 確認画面へ 次へ].freeze

  # 成功判定用キーワード
  SUCCESS_PATTERNS = %w[ありがとう 完了 受付 送信しました 送信完了 thank success
                        受け付けました 受付いたしました 送信いたしました お問い合わせいただき
                        送信されました].freeze

  # 営業禁止検出用キーワード（これらを含むページは送信をスキップ）
  NO_SALES_PATTERNS = %w[
    営業禁止 営業お断り セールスお断り 営業メールお断り
    営業目的のお問い合わせはお断り 営業のご連絡はお断り
    営業はご遠慮 営業のメールはご遠慮 営業等のご連絡はお控え
    営業についてはお断り 売り込みお断り 売込みお断り
  ].freeze

  attr_reader :driver, :customer, :result

  # アラートのエラー検出用キーワード
  ALERT_ERROR_PATTERNS = %w[未入力 エラー error 入力してください 必須 required チェックを入れて].freeze

  # ページ内エラー検出用CSSセレクタ（送信後の偽陽性防止用）
  PAGE_ERROR_CSS = [
    '.error:not([style*="display: none"])',
    '.err:not([style*="display: none"])',
    '.alert-danger', '.alert-error',
    '.validation-error', '.form-error',
    '.wpcf7-not-valid-tip',
    '[class*="error"]:not(input):not(select):not(textarea)',
    '[class*="invalid"]:not(input):not(select):not(textarea)',
  ].freeze

  # ページ内エラーテキストパターン（CSS検出と併用）
  PAGE_ERROR_PATTERNS = [
    '入力内容をご確認', '入力内容を確認してください', '入力内容に誤り',
    '正しく入力してください', '再度ご確認ください', 'もう一度ご確認',
    'メールアドレスが正しくありません', 'メールアドレスを正しく',
    '有効なメールアドレス', '入力されていません', '入力に誤りがあります',
    'お確かめ下さい', 'お確かめください', '内容をお確かめ',
  ].freeze

  def initialize(debug: false, confirm_mode: false, save_to_db: false, headless: false, confirm_callback: nil)
    @driver = nil
    @result = { status: nil, message: nil }
    @debug = debug
    @confirm_mode = confirm_mode  # trueの場合、送信前に停止して確認を待つ
    @save_to_db = save_to_db      # trueの場合、送信結果をDBに保存
    @headless = headless           # trueの場合、ヘッドレスモードで実行
    @alert_had_error = false      # アラートにエラーメッセージがあったか
    @confirm_callback = confirm_callback  # 確認モード時の待機処理（Proc）
  end

  # ブラウザを起動
  def setup_driver
    options = Selenium::WebDriver::Chrome::Options.new
    if @headless
      options.add_argument('--headless=new')  # 新ヘッドレスモード（Chrome 109+、旧--headlessより互換性が高い）
    end
    options.add_argument('--disable-gpu')
    options.add_argument('--no-sandbox')
    options.add_argument('--disable-dev-shm-usage')
    options.add_argument('--window-size=1280,800')
    options.add_argument('--ignore-certificate-errors')
    options.add_argument('--disable-blink-features=AutomationControlled')  # Selenium検知回避
    options.add_argument('--user-agent=Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36')

    @driver = Selenium::WebDriver.for(:chrome, options: options)
    @driver.manage.timeouts.implicit_wait = 5
  end

  # ブラウザを終了
  def teardown_driver
    @driver&.quit
    @driver = nil
  end

  # 送信実行
  def send_to_customer(customer)
    @customer = customer
    @result = { status: nil, message: nil }
    @alert_had_error = false

    # NGブラックリストチェック（contact_url設定済みの場合）
    if customer.contact_url.present? && blocked_url?(customer.contact_url)
      @result = { status: 'NG対象', message: "ブラックリスト該当URL: #{customer.contact_url}" }
      save_result_to_db if @save_to_db
      return @result
    end

    # contact_urlがない場合 → 自動検出を試みる
    if customer.contact_url.blank?
      if customer.url.present?
        log "contact_url未設定 → HPから自動検出を試みます"
        detector = ContactUrlDetector.new(debug: @debug, headless: @headless)
        detection = detector.detect(customer)
        if detection[:status] == 'detected'
          # 検出結果のNGブラックリストチェック
          if blocked_url?(detection[:contact_url])
            @result = { status: 'NG対象', message: "自動検出URLがブラックリスト該当: #{detection[:contact_url]}" }
            save_result_to_db if @save_to_db
            return @result
          end
          customer.update_column(:contact_url, detection[:contact_url])
          log "自動検出成功: #{detection[:contact_url]}"
        else
          @result = { status: 'フォーム未検出', message: "自動検出失敗: #{detection[:message]}" }
          save_result_to_db if @save_to_db
          return @result
        end
      else
        @result = { status: 'フォーム未検出', message: 'URLが設定されていません。顧客編集画面でURLを設定してください。' }
        save_result_to_db if @save_to_db
        return @result
      end
    end

    begin
      setup_driver

      # フォームにアクセス
      log "アクセス中: #{customer.contact_url}"
      driver.navigate.to(customer.contact_url)
      sleep 3 # ページ読み込み待機

      # 営業禁止チェック
      if page_has_no_sales_warning?
        @result = { status: '営業禁止', message: 'ページ内に営業禁止ワードが検出されました' }
        teardown_driver
        return @result
      end

      # フォームを検出して入力
      filled = fill_form
      log "入力完了: #{filled}フィールド"

      if filled >= 2
        if @confirm_mode
          # 確認モード：送信せずに停止
          log "=== 確認モード ==="
          log "フォーム入力完了。ブラウザで内容を確認してください。"
          log "送信する場合は手動で送信ボタンをクリックしてください。"
          log "確認待ち..."
          if @confirm_callback
            @confirm_callback.call
          else
            puts "\n" + "=" * 50
            puts "【確認モード】フォーム入力完了"
            puts "=" * 50
            puts "ブラウザで入力内容を確認してください。"
            puts ""
            puts "  → 送信する場合：ブラウザで送信ボタンをクリック"
            puts "  → 送信しない場合：そのままEnterを押す"
            puts ""
            puts "確認が終わったらEnterキーを押してください..."
            $stdin.gets
          end
          teardown_driver  # 確認後にブラウザを閉じる
          @result = { status: '確認完了', message: "#{filled}フィールド入力済み（手動確認モード）" }
        else
          # 通常モード：自動送信
          if click_submit
            log "送信ボタンクリック成功（1回目）"

            # 確認ダイアログがあれば承認
            handle_alert

            sleep 5 # 送信後の待機（AJAX応答やページ遷移を待つ）

            # 確認画面の場合、もう一度送信ボタンをクリック
            if confirmation_page?
              log "確認画面を検出"
              if click_submit
                log "送信ボタンクリック成功（2回目：確認画面）"
                handle_alert
                sleep 4 # 確認画面後はより長く待機（完了ページ遷移を待つ）
              end
            end

            # 成功判定（リトライ付き）
            if check_success?
              @result = { status: '自動送信成功', message: '送信が完了しました' }
            else
              # 初回判定で失敗: 追加待機して再判定（AJAX応答やページ遷移の遅延対策）
              log "成功未検出、追加待機後に再判定..."
              sleep 3
              if check_success?
                @result = { status: '自動送信成功', message: '送信が完了しました' }
              elsif page_has_captcha?
                @result = { status: 'CAPTCHA NG', message: 'reCAPTCHA/CAPTCHA が検出されました' }
              else
                @result = { status: '自動送信失敗', message: '送信後の確認ができませんでした' }
              end
            end
          else
            @result = { status: '自動送信失敗', message: '送信ボタンが見つかりませんでした' }
          end
          teardown_driver  # 通常モード完了後にブラウザを閉じる
        end
      else
        @result = { status: 'フォーム未検出', message: "入力フィールドが不足（#{filled}フィールドのみ）" }
        teardown_driver
      end

    rescue Selenium::WebDriver::Error::WebDriverError => e
      @result = { status: 'アクセス失敗', message: e.message }
      teardown_driver
    rescue StandardError => e
      @result = { status: 'エラー', message: e.message }
      teardown_driver
    end

    # 送信結果をDBに保存
    save_result_to_db if @save_to_db

    @result
  end

  # NGブラックリスト判定（URL部分一致）
  def blocked_url?(url)
    return false if url.blank?
    patterns = defined?(BLOCKED_URL_PATTERNS) ? BLOCKED_URL_PATTERNS : []
    patterns.any? { |pattern| url.downcase.include?(pattern.downcase) }
  end

  # 送信結果をDBに保存
  def save_result_to_db
    # Rails環境でない場合はスキップ
    return unless defined?(ActiveRecord::Base)
    return unless @customer.respond_to?(:id) && @customer.id.present?

    begin
      # Callモデルを文字列から取得（Railsの自動ロードをトリガー）
      call_class = "Call".constantize
      call = call_class.new(
        customer_id: @customer.id,
        status: @result[:status],
        comment: "【フォーム送信】#{@result[:message]}",
        call_type: 'form'
      )
      # バリデーションをスキップして保存（Callモデルは電話用のバリデーションがあるため）
      call.save!(validate: false)
      log "送信結果をDBに保存しました (Call ID: #{call.id})"
    rescue StandardError => e
      log "DB保存エラー: #{e.message}"
    end
  end

  private

  def log(message)
    puts "[FormSender] #{message}" if @debug
  end

  # フリガナ欄がカタカナかひらがなかを自動判定
  # @return [Boolean] true=カタカナ, false=ひらがな
  def detect_kana_type(text, name_attr)
    # 1. テキスト内のキーワードで判定（従来ロジック）
    return true  if text.include?('カタカナ') || text.include?('フリガナ')
    return false if text.include?('ひらがな') || text.include?('ふりがな')

    # 2. placeholder属性にカタカナ/ひらがなの例があるかチェック
    if @current_input
      begin
        ph = @current_input.attribute('placeholder') || ''
        return true  if ph.match?(/[\p{Katakana}]{2,}/)  # カタカナ2文字以上（例: ヤマグチ）
        return false if ph.match?(/[\p{Hiragana}]{2,}/)  # ひらがな2文字以上（例: やまぐち）
      rescue StandardError
        # 無視
      end

      # 3. 周辺のラベル・親要素のテキストからカタカナ指定を検出
      begin
        # for属性ラベル
        input_id = @current_input.attribute('id')
        if input_id.to_s.strip != ''
          label = driver.find_element(:css, "label[for='#{input_id}']") rescue nil
          if label
            lt = label.text.to_s
            return true  if lt.include?('フリガナ') || lt.include?('カタカナ') || lt.include?('カナ')
            return false if lt.include?('ふりがな') || lt.include?('ひらがな')
          end
        end
      rescue StandardError
        # 無視
      end

      begin
        # 親・祖父母要素のテキストを確認
        parent = @current_input.find_element(:xpath, 'ancestor::*[2]') rescue nil
        if parent
          pt = parent.text.to_s[0..200]  # 長すぎるテキストは切り詰め
          return true  if pt.include?('フリガナ') || pt.include?('カタカナ')
          return false if pt.include?('ふりがな') || pt.include?('ひらがな')
        end
      rescue StandardError
        # 無視
      end

      # 4. テーブルレイアウト: 同じ行のth要素をチェック
      begin
        row = @current_input.find_element(:xpath, 'ancestor::tr')
        th = row.find_element(:css, 'th')
        th_text = th.text.to_s
        return true  if th_text.include?('フリガナ') || th_text.include?('カタカナ') || th_text.include?('カナ')
        return false if th_text.include?('ふりがな') || th_text.include?('ひらがな')
      rescue StandardError
        # 無視
      end

      # 5. dl/dt/ddレイアウト
      begin
        dd = @current_input.find_element(:xpath, 'ancestor::dd')
        dt = dd.find_element(:xpath, 'preceding-sibling::dt[1]')
        dt_text = dt.text.to_s
        return true  if dt_text.include?('フリガナ') || dt_text.include?('カタカナ') || dt_text.include?('カナ')
        return false if dt_text.include?('ふりがな') || dt_text.include?('ひらがな')
      rescue StandardError
        # 無視
      end
    end

    # 6. name属性のヒューリスティック判定
    #    "kana" / "furigana" / "カナ" を含むが "hira" / "ひら" を含まない場合はカタカナの可能性が高い
    if name_attr.match?(/kana|furigana|カナ/i) && !name_attr.match?(/hira|ひら/i)
      log "    カナ判定: name属性「#{name_attr}」からカタカナと推定"
      return true
    end

    # デフォルト: ひらがな
    false
  end

  # 電話番号フィールドのハイフン有無を自動判定
  def detect_tel_format
    begin
      tel_inputs = driver.find_elements(:css, 'input')
      tel_inputs.each do |input|
        next unless input.displayed?

        name_attr = input.attribute('name')&.downcase || ''
        id_attr = input.attribute('id')&.downcase || ''
        placeholder = input.attribute('placeholder') || ''
        pattern = input.attribute('pattern') || ''
        input_type = input.attribute('type')&.downcase || ''

        # 電話番号フィールドかどうか判定（ラベルテキストも含む）
        label_text = get_label_text(input).downcase rescue ''
        all_text = "#{name_attr} #{id_attr} #{label_text}"
        is_tel = FIELD_PATTERNS[:tel].any? { |p| all_text.include?(p) } || input_type == 'tel'
        next unless is_tel

        # 分割フィールド（tel1, tel2, tel3）はスキップ
        next if name_attr =~ /(?:tel|phone|denwa|電話).*(?:[123]$|\[\d\]$)/i

        # placeholder にハイフンなしの数字パターンがあればハイフン不要
        if placeholder =~ /\A[0-9]{10,11}\z/
          log "電話番号: ハイフン不要（placeholder: #{placeholder}）"
          return SENDER_INFO[:tel_no_hyphen]
        end

        # placeholder にハイフン付きパターンがあればハイフン必要
        if placeholder =~ /[0-9]+-[0-9]+-[0-9]+/
          log "電話番号: ハイフン必要（placeholder: #{placeholder}）"
          return SENDER_INFO[:tel]
        end

        # pattern属性で判定（数字のみを要求する場合）
        if pattern =~ /\\d\{10|\\d\{11|\[0-9\]\{10|\[0-9\]\{11|^\d+$/
          log "電話番号: ハイフン不要（pattern: #{pattern}）"
          return SENDER_INFO[:tel_no_hyphen]
        end

        # pattern属性があり、ハイフンを許可していない場合
        if !pattern.empty? && !pattern.include?('-')
          log "電話番号: ハイフン不要（patternにハイフン未含: #{pattern}）"
          return SENDER_INFO[:tel_no_hyphen]
        end

        # type="tel" でmaxlengthが11以下ならハイフン不要の可能性が高い
        maxlength = input.attribute('maxlength')&.to_i
        if maxlength && maxlength <= 11 && maxlength >= 10
          log "電話番号: ハイフン不要（maxlength: #{maxlength}）"
          return SENDER_INFO[:tel_no_hyphen]
        end

        # type="tel"/"number" はハイフンを拒否するバリデーションが多いため
        # 明確にハイフン必要と判定されなかった場合はハイフンなしを使用
        if input_type == 'tel' || input_type == 'number'
          log "電話番号: ハイフン不要（type=#{input_type}フィールド）"
          return SENDER_INFO[:tel_no_hyphen]
        end
      end
    rescue StandardError => e
      log "電話番号フォーマット判定エラー: #{e.message}"
    end

    # デフォルトはハイフン付き
    log "電話番号: デフォルト（ハイフン付き）"
    SENDER_INFO[:tel]
  end

  # 郵便番号のmaxlengthから入力すべき値を判定
  # maxlength=3 → 前半3桁、maxlength=4 → 後半4桁、それ以外 → フル
  def zip_value_by_maxlength
    return SENDER_INFO[:zip] unless @current_input

    begin
      maxlength = @current_input.attribute('maxlength')&.to_i
      if maxlength && maxlength == 3
        log "    郵便番号: maxlength=3 → 前半3桁"
        return SENDER_INFO[:zip1]
      elsif maxlength && maxlength == 4
        log "    郵便番号: maxlength=4 → 後半4桁"
        return SENDER_INFO[:zip2]
      end
    rescue StandardError
    end

    SENDER_INFO[:zip]
  end

  # 名前・カナ・住所の分割フィールド存在を事前判定
  def detect_name_split_fields
    @has_name2_field = false
    @has_kana2_field = false
    @has_pref_field = false
    begin
      all_elements = driver.find_elements(:css, 'input, select')
      all_elements.each do |el|
        next unless el.displayed?
        name = el.attribute('name')&.downcase || ''
        if name =~ /name.*2$/i && name !~ /kana|namea|furi/i
          @has_name2_field = true
        end
        if name =~ /(?:kana|namea|furi).*2$/i
          @has_kana2_field = true
        end
        if FIELD_PATTERNS[:prefecture].any? { |p| name.include?(p) }
          @has_pref_field = true
        end
      end
      log "名前分割検出: name2=#{@has_name2_field}, kana2=#{@has_kana2_field}" if @has_name2_field || @has_kana2_field
      log "住所分割検出: 都道府県フィールドあり" if @has_pref_field
    rescue StandardError => e
      log "分割フィールド検出エラー: #{e.message}"
    end
  end

  # ページ内に営業禁止ワードがあるかチェック
  def page_has_no_sales_warning?
    begin
      page_text = driver.find_element(:css, 'body').text
      NO_SALES_PATTERNS.each do |pattern|
        if page_text.include?(pattern)
          log "営業禁止ワード検出: #{pattern}"
          return true
        end
      end
    rescue StandardError => e
      log "営業禁止チェックエラー: #{e.message}"
    end
    false
  end

  # ページ内にreCAPTCHA/CAPTCHAがあるかチェック
  def page_has_captcha?
    begin
      page_source = driver.page_source
      captcha_patterns = %w[recaptcha g-recaptcha hcaptcha cf-turnstile]
      captcha_text_patterns = ['私はロボットではありません', 'I\'m not a robot']
      # HTML属性/クラスで検出
      return true if captcha_patterns.any? { |p| page_source.downcase.include?(p) }
      # ページテキストで検出
      body_text = driver.find_element(:css, 'body').text rescue ''
      return true if captcha_text_patterns.any? { |p| body_text.include?(p) }
    rescue StandardError => e
      log "CAPTCHA検出エラー: #{e.message}"
    end
    false
  end

  # 同意チェックボックス検出用キーワード
  CONSENT_PATTERNS = %w[同意 agree 規約 プライバシー privacy policy 承諾 確認しました 了承 confirm 個人情報].freeze

  # ラジオボタン選択：優先するキーワード
  RADIO_PREFER_PATTERNS = %w[その他 他 other お問い合わせ ご相談 相談 サービス 一般 general].freeze

  # ラジオボタン選択：避けるキーワード
  RADIO_AVOID_PATTERNS = %w[採用 求人 recruit 個人情報 プライバシー privacy 苦情 クレーム complaint 返品 返金].freeze

  # 必須マーク検出パターン
  REQUIRED_MARKERS = ['*', '※', '必須', 'required', '（必須）', '(必須)'].freeze

  # フォームに入力
  def fill_form
    filled_count = 0

    # 電話番号のハイフン有無を事前判定
    @current_tel_value = detect_tel_format

    # 名前・カナの分割フィールドを事前判定
    detect_name_split_fields

    # 同意チェックボックスをチェック
    check_consent_boxes

    # ラジオボタングループを処理
    handle_radio_buttons

    # 必須チェックボックスグループを処理
    handle_required_checkboxes

    # 全ての入力可能な要素を取得
    inputs = driver.find_elements(:css, 'input:not([type="hidden"]):not([type="submit"]):not([type="button"]):not([type="radio"]):not([type="checkbox"]), textarea, select')
    log "入力要素数: #{inputs.size}"

    inputs.each_with_index do |input, idx|
      next unless input.displayed?

      # 要素の属性を取得
      tag_name = input.tag_name.downcase
      input_type = input.attribute('type')&.downcase || 'text'
      name_attr = input.attribute('name')&.downcase || ''
      id_attr = input.attribute('id')&.downcase || ''
      placeholder = input.attribute('placeholder')&.downcase || ''

      # 周辺のラベルテキストを取得
      label_text = get_label_text(input)

      # フィールド判定用テキスト（必須マーカーを除去してパターンマッチ精度を上げる）
      clean_name = name_attr.gsub(/[（(]必須[）)]|※必須|必須/, '').strip
      all_text = "#{clean_name} #{id_attr} #{placeholder} #{label_text}".downcase

      # 必須判定（name属性内の必須マークも確認）
      name_raw = input.attribute('name') || ''
      is_required = required_field?(label_text, input) ||
                    REQUIRED_MARKERS.any? { |marker| name_raw.include?(marker) }
      required_mark = is_required ? '【必須】' : ''
      log "  [#{idx}] tag=#{tag_name}, name=#{name_attr}, label=#{label_text} #{required_mark}"

      # 重要フィールド判定（名前、メール、電話は必須でなくても入力）
      is_important = important_field?(all_text, name_attr, tag_name)

      # 必須でも重要でもないフィールドはスキップ
      unless is_required || is_important
        log "    → スキップ（必須/重要でない）"
        next
      end

      # フィールドタイプを判定して入力（カナ判定用に現在の入力要素を保持）
      @current_input = input
      value = determine_value(all_text, tag_name, name_attr)

      # パターン不一致の必須フィールドはラベルから周辺テキストを広く取得して再判定
      if value.nil? && is_required
        extended_label = get_extended_label(input)
        if extended_label.present?
          extended_text = "#{extended_label} #{all_text}".downcase
          value = determine_value(extended_text, tag_name, name_attr)
          log "    → 拡張ラベル判定: #{extended_label}" if value
        end
      end

      if value
        begin
          if tag_name == 'select'
            # セレクトボックスの場合
            select = Selenium::WebDriver::Support::Select.new(input)
            # 完全一致で選択を試みる
            begin
              select.select_by(:text, value)
              filled_count += 1
              log "    → 選択成功: #{value}"
            rescue Selenium::WebDriver::Error::NoSuchElementError
              # 部分一致で選択を試みる
              options = select.options
              matched = options.find { |opt| opt.text.include?(value) || value.include?(opt.text) }
              if matched
                select.select_by(:text, matched.text)
                filled_count += 1
                log "    → 選択成功（部分一致）: #{matched.text}"
              else
                log "    → 選択失敗: #{value}に一致する選択肢なし"
              end
            end
          else
            # テキスト入力の場合
            input.clear
            input.send_keys(value)
            filled_count += 1
            log "    → 入力成功: #{value[0..20]}..."
          end
        rescue StandardError => e
          log "    → 入力失敗: #{e.message}"
        end
      elsif tag_name == 'select' && is_required
        # 必須セレクトでパターン不一致: 最初の有効な選択肢を自動選択
        begin
          select = Selenium::WebDriver::Support::Select.new(input)
          options = select.options
          # 空やプレースホルダ以外の最初の選択肢を選ぶ
          valid_option = options.find do |opt|
            text = opt.text.strip
            text.present? && !text.match?(/\A[-ー―]+\z/) &&
              !%w[選択してください 選択して下さい --- 未選択].include?(text)
          end
          if valid_option && valid_option != options.first
            select.select_by(:text, valid_option.text)
            filled_count += 1
            log "    → 必須セレクト自動選択: #{valid_option.text}"
          elsif options.size >= 2
            select.select_by(:index, 1)
            filled_count += 1
            log "    → 必須セレクト自動選択（2番目）: #{options[1].text}"
          end
        rescue StandardError => e
          log "    → 必須セレクト選択失敗: #{e.message}"
        end
      end
    end

    # フォーム入力後に同意チェックボックスを再チェック（ページ読み込み遅延対策）
    recheck_consent_boxes

    filled_count
  end

  # 重要フィールドかどうか判定（必須マークがなくても入力すべき最低限のフィールド）
  def important_field?(text, name_attr, tag_name)
    # メッセージ欄のtextareaのみ重要（住所等のtextareaは除外）
    if tag_name == 'textarea'
      return true if FIELD_PATTERNS[:message].any? { |p| text.include?(p) || name_attr.include?(p) }
      return false  # 住所などのtextareaは必須でなければスキップ
    end

    # 名前フィールド（部署名は除外）
    if FIELD_PATTERNS[:name].any? { |p| text.include?(p) || name_attr.include?(p) }
      return false if text.include?('部署') || name_attr.include?('部署')
      return true
    end

    # メールフィールド
    return true if FIELD_PATTERNS[:email].any? { |p| text.include?(p) || name_attr.include?(p) }

    # 電話番号フィールド
    return true if FIELD_PATTERNS[:tel].any? { |p| text.include?(p) || name_attr.include?(p) }

    # 会社名フィールド
    return true if FIELD_PATTERNS[:company].any? { |p| text.include?(p) || name_attr.include?(p) }

    # フリガナフィールド（日本のフォームでは一般的に必要）
    return true if FIELD_PATTERNS[:name_kana].any? { |p| text.include?(p) || name_attr.include?(p) }

    # 郵便番号フィールド
    return true if FIELD_PATTERNS[:zip].any? { |p| text.include?(p) || name_attr.include?(p) }

    # 住所フィールド
    return true if FIELD_PATTERNS[:address].any? { |p| text.include?(p) || name_attr.include?(p) }

    false
  end

  # 必須フィールドかどうか判定（厳密版：ラベル直後のマークのみ）
  def required_field?(label_text, input)
    # 1. HTML属性で判定
    return true if input.attribute('required').present?
    return true if input.attribute('aria-required') == 'true'

    # 2. ラベルテキストに必須マークがあるか（直接含まれている場合のみ）
    return true if REQUIRED_MARKERS.any? { |marker| label_text.include?(marker) }

    # 3. 直近のラベル要素のみチェック（親要素全体ではなく）
    input_id = input.attribute('id')
    if input_id.present?
      begin
        label = driver.find_element(:css, "label[for='#{input_id}']")
        label_full_text = label.text
        return true if REQUIRED_MARKERS.any? { |marker| label_full_text.include?(marker) }
      rescue Selenium::WebDriver::Error::NoSuchElementError
        # 無視
      end
    end

    # 4. 直前の兄弟要素がラベルの場合のみチェック
    begin
      prev = input.find_element(:xpath, 'preceding-sibling::*[1]')
      if %w[label span th dt].include?(prev.tag_name.downcase)
        prev_text = prev.text rescue ''
        return true if REQUIRED_MARKERS.any? { |marker| prev_text.include?(marker) }
      end
    rescue StandardError
      # 無視
    end

    # 5. 親がlabel要素の場合
    begin
      parent = input.find_element(:xpath, '..')
      if parent.tag_name.downcase == 'label'
        parent_text = parent.text rescue ''
        return true if REQUIRED_MARKERS.any? { |marker| parent_text.include?(marker) }
      end
    rescue StandardError
      # 無視
    end

    # 6. テーブルレイアウト: 同じ行のth要素をチェック
    begin
      row = input.find_element(:xpath, 'ancestor::tr')
      th = row.find_element(:css, 'th')
      th_text = th.text rescue ''
      return true if REQUIRED_MARKERS.any? { |marker| th_text.include?(marker) }
    rescue StandardError
      # 無視
    end

    # 7. dl/dt/ddレイアウト: 前のdt要素をチェック
    begin
      dd = input.find_element(:xpath, 'ancestor::dd')
      dt = dd.find_element(:xpath, 'preceding-sibling::dt[1]')
      dt_text = dt.text rescue ''
      return true if REQUIRED_MARKERS.any? { |marker| dt_text.include?(marker) }
    rescue StandardError
      # 無視
    end

    false
  end

  # ラベルテキストを取得
  def get_label_text(input)
    # for属性でラベルを検索
    input_id = input.attribute('id')
    if input_id.present?
      begin
        label = driver.find_element(:css, "label[for='#{input_id}']")
        return label.text.downcase if label
      rescue Selenium::WebDriver::Error::NoSuchElementError
        # 見つからない場合は続行
      end
    end

    # 親要素からラベルを検索
    begin
      parent = input.find_element(:xpath, '..')
      label = parent.find_element(:css, 'label, th, dt, .label')
      return label.text.downcase if label
    rescue Selenium::WebDriver::Error::NoSuchElementError
      # 見つからない場合は続行
    end

    # 前の兄弟要素を検索
    begin
      prev_sibling = input.find_element(:xpath, 'preceding-sibling::*[1]')
      return prev_sibling.text.downcase if prev_sibling
    rescue Selenium::WebDriver::Error::NoSuchElementError
      # 見つからない場合
    end

    ''
  end

  # 拡張ラベル取得（get_label_textで取れなかった場合のフォールバック）
  def get_extended_label(input)
    # テーブルレイアウト: 同じ行のth要素を探す
    begin
      row = input.find_element(:xpath, 'ancestor::tr')
      th = row.find_element(:css, 'th')
      text = th.text.downcase
      return text if text.present?
    rescue Selenium::WebDriver::Error::NoSuchElementError
      # 無視
    end

    # dl/dt/ddレイアウト: 前のdt要素を探す
    begin
      dd = input.find_element(:xpath, 'ancestor::dd')
      dt = dd.find_element(:xpath, 'preceding-sibling::dt[1]')
      text = dt.text.downcase
      return text if text.present?
    rescue Selenium::WebDriver::Error::NoSuchElementError
      # 無視
    end

    # 2階層上の親からラベル要素を探す
    begin
      grandparent = input.find_element(:xpath, 'ancestor::*[3]')
      labels = grandparent.find_elements(:css, 'label, th, dt, .label, p')
      labels.each do |label|
        text = label.text.downcase
        return text if text.present? && text.length < 50
      end
    rescue Selenium::WebDriver::Error::NoSuchElementError
      # 無視
    end

    # placeholder属性（日本語が含まれている場合のみ）
    placeholder = input.attribute('placeholder') || ''
    return placeholder.downcase if placeholder =~ /[\p{Hiragana}\p{Katakana}\p{Han}]/

    ''
  end

  # テキストからフィールドタイプを判定して値を返す
  def determine_value(text, tag_name, name_attr = '')
    # name属性から必須マーカーを除去して判定精度を上げる
    name_attr = name_attr.gsub(/[（(]必須[）)]|※必須|必須/, '').strip
    # メールアドレス確認用
    if FIELD_PATTERNS[:email_confirm].any? { |p| text.include?(p) }
      return SENDER_INFO[:email]
    end

    # メッセージ（textareaでも住所欄などは除外）
    if tag_name == 'textarea'
      # 住所欄の場合は住所を入力（都道府県フィールドがある場合は番地のみ）
      if FIELD_PATTERNS[:address].any? { |p| text.include?(p) || name_attr.include?(p) }
        return @has_pref_field ? SENDER_INFO[:address_street] : SENDER_INFO[:address]
      end
      # それ以外のtextareaはメッセージ
      return SENDER_INFO[:message]
    end

    # 部署名はスキップ（または「-」を入力）
    if text.include?('部署') || name_attr.include?('部署')
      return nil
    end

    # === 会社名（必須の場合は「自営業」を入力） ===
    if FIELD_PATTERNS[:company].any? { |p| name_attr.include?(p) || text.include?(p) }
      return '自営業'
    end

    # === 分割フィールドの検出（name属性で判定） ===

    # 電話番号（3分割: tel1/tel2/tel3 or [data][0]/[data][1]/[data][2]）
    if name_attr =~ /(?:tel|phone|denwa|電話).*(?:1$|\[0\]$)/i
      return SENDER_INFO[:tel1]
    end
    if name_attr =~ /(?:tel|phone|denwa|電話).*(?:2$|\[1\]$)/i
      return SENDER_INFO[:tel2]
    end
    if name_attr =~ /(?:tel|phone|denwa|電話).*(?:3$|\[2\]$)/i
      return SENDER_INFO[:tel3]
    end

    # 郵便番号（2分割: zip1/zip2, zip/zip1, [data][0]/[data][1] 等）
    if name_attr =~ /(?:zip|postal|yubin|郵便).*(?:1$|\[0\]$)/i
      return zip_value_by_maxlength
    end
    if name_attr =~ /(?:zip|postal|yubin|郵便).*(?:2$|\[1\]$)/i
      return zip_value_by_maxlength
    end

    # ふりがな/フリガナ（2分割）
    if name_attr =~ /namea.*1$|kana.*1$|kana.*sei|furi.*1|furi.*sei/i
      return detect_kana_type(text, name_attr) ? SENDER_INFO[:name_kana_sei] : SENDER_INFO[:name_hira_sei]
    end
    if name_attr =~ /namea.*2$|kana.*2$|kana.*mei|furi.*2|furi.*mei/i
      return detect_kana_type(text, name_attr) ? SENDER_INFO[:name_kana_mei] : SENDER_INFO[:name_hira_mei]
    end

    # 名前（2分割: name1/name2）
    # 末尾が数字の場合のみ分割とみなす（meiやseiが含まれるだけでは分割としない）
    if name_attr =~ /name.*1$/i && name_attr !~ /kana|namea|furi/i
      return SENDER_INFO[:name_sei]
    end
    if name_attr =~ /name.*2$/i && name_attr !~ /kana|namea|furi/i
      return SENDER_INFO[:name_mei]
    end
    # ラベルに「姓」「名」が明示されている場合のみ分割
    if text.include?('姓') && !text.include?('氏名') && !text.include?('名前')
      return SENDER_INFO[:name_sei]
    end
    # 「名」が単独で使われている場合のみ分割（「担当者名」「御社名」等の複合語は除外）
    if text =~ /(?<!\p{Han})名(?!\p{Han})/ &&
        !text.include?('氏名') && !text.include?('名前') &&
        !text.include?('会社名') && !text.include?('お名前')
      return SENDER_INFO[:name_mei]
    end

    # === 通常フィールド（分割でない場合） ===

    # ふりがな/フリガナ - フルネーム（kana2がある場合は姓のみ）
    if FIELD_PATTERNS[:name_kana].any? { |p| text.include?(p) }
      if @has_kana2_field
        return detect_kana_type(text, name_attr) ? SENDER_INFO[:name_kana_sei] : SENDER_INFO[:name_hira_sei]
      end
      return detect_kana_type(text, name_attr) ? SENDER_INFO[:name_kana] : SENDER_INFO[:name_hira]
    end

    # 名前 - フルネーム（name2がある場合は姓のみ）
    if FIELD_PATTERNS[:name].any? { |p| text.include?(p) }
      return @has_name2_field ? SENDER_INFO[:name_sei] : SENDER_INFO[:name]
    end

    # メールアドレス
    if FIELD_PATTERNS[:email].any? { |p| text.include?(p) }
      return SENDER_INFO[:email]
    end

    # 電話番号 - フル（placeholder/patternからハイフン有無を自動判定）
    if FIELD_PATTERNS[:tel].any? { |p| text.include?(p) }
      return @current_tel_value || SENDER_INFO[:tel]
    end

    # 郵便番号 - フル（maxlengthで分割フィールドの可能性を判定）
    if FIELD_PATTERNS[:zip].any? { |p| text.include?(p) }
      return zip_value_by_maxlength
    end

    # 都道府県（セレクトボックス用）
    if FIELD_PATTERNS[:prefecture].any? { |p| text.include?(p) || name_attr.include?(p) }
      return SENDER_INFO[:prefecture]
    end

    # 住所（都道府県フィールドがある場合は番地のみ）
    if FIELD_PATTERNS[:address].any? { |p| text.include?(p) || name_attr.include?(p) }
      return @has_pref_field ? SENDER_INFO[:address_street] : SENDER_INFO[:address]
    end

    nil
  end

  # ラジオボタングループを処理
  def handle_radio_buttons
    # ラジオボタンをグループ（name属性）ごとに収集
    radio_buttons = driver.find_elements(:css, 'input[type="radio"]')
    groups = radio_buttons.group_by { |r| r.attribute('name') }

    groups.each do |name, radios|
      next if radios.empty?
      next if radios.any?(&:selected?)  # 既に選択済みならスキップ

      visible_radios = radios.select(&:displayed?)
      next if visible_radios.empty?

      # このラジオグループが必須かどうか判定
      group_label = get_radio_group_label(visible_radios.first)
      is_required = required_field?(group_label, visible_radios.first)

      unless is_required
        log "  ラジオボタン[#{name}]: 必須でないためスキップ"
        next
      end

      # 各選択肢のラベルを取得
      options = visible_radios.map do |radio|
        label = get_radio_label(radio)
        { radio: radio, label: label }
      end

      # 優先する選択肢を探す
      selected = nil

      # 1. 「その他」などの優先キーワードを含む選択肢
      RADIO_PREFER_PATTERNS.each do |pattern|
        selected ||= options.find { |opt| opt[:label].include?(pattern) }
      end

      # 2. 避けるべきキーワードを含まない選択肢（優先が見つからない場合）
      unless selected
        safe_options = options.reject do |opt|
          RADIO_AVOID_PATTERNS.any? { |avoid| opt[:label].include?(avoid) }
        end
        selected = safe_options.first if safe_options.any?  # 最初の安全な選択肢
      end

      # 3. それでも見つからなければ最初の選択肢
      selected ||= options.first

      # 選択実行
      if selected
        begin
          driver.execute_script("arguments[0].click();", selected[:radio])
          log "  → ラジオボタン選択[#{name}]: #{selected[:label]}"
        rescue StandardError => e
          log "  → ラジオボタン選択失敗[#{name}]: #{e.message}"
        end
      end
    end
  end

  # ラジオボタングループのラベルを取得
  def get_radio_group_label(radio)
    # 親要素を遡ってラベルを探す
    begin
      # fieldsetのlegendを探す
      fieldset = radio.find_element(:xpath, 'ancestor::fieldset')
      legend = fieldset.find_element(:css, 'legend')
      return legend.text.downcase if legend
    rescue Selenium::WebDriver::Error::NoSuchElementError
      # 無視
    end

    # テーブルのth/tdを探す
    begin
      row = radio.find_element(:xpath, 'ancestor::tr')
      th = row.find_element(:css, 'th')
      return th.text.downcase if th
    rescue Selenium::WebDriver::Error::NoSuchElementError
      # 無視
    end

    # 親のdivなどからラベルを探す
    begin
      parent = radio.find_element(:xpath, './ancestor::*[contains(@class, "form-group") or contains(@class, "field")]')
      label = parent.find_element(:css, 'label, .label, dt')
      return label.text.downcase if label
    rescue Selenium::WebDriver::Error::NoSuchElementError
      # 無視
    end

    ''
  end

  # ラジオボタン個別のラベルを取得
  def get_radio_label(radio)
    # for属性でラベルを検索
    radio_id = radio.attribute('id')
    if radio_id.present?
      begin
        label = driver.find_element(:css, "label[for='#{radio_id}']")
        return label.text.downcase if label
      rescue Selenium::WebDriver::Error::NoSuchElementError
        # 無視
      end
    end

    # 次の兄弟テキストまたはlabel
    begin
      parent = radio.find_element(:xpath, '..')
      return parent.text.downcase
    rescue Selenium::WebDriver::Error::NoSuchElementError
      # 無視
    end

    radio.attribute('value')&.downcase || ''
  end

  # 必須チェックボックスグループを処理（件名選択など）
  def handle_required_checkboxes
    checkboxes = driver.find_elements(:css, 'input[type="checkbox"]')
    log "チェックボックス総数: #{checkboxes.size}"
    groups = checkboxes.group_by { |c| c.attribute('name') }

    groups.each do |name, boxes|
      next if boxes.empty?
      next if boxes.any?(&:selected?)  # 既に選択済みならスキップ

      visible_boxes = boxes.select(&:displayed?)
      next if visible_boxes.empty?

      # このチェックボックスグループが必須かどうか判定
      group_label = get_checkbox_group_label(visible_boxes.first)
      log "  チェックボックスグループ[#{name}]: ラベル=「#{group_label}」"

      # 必須マークがあるかチェック
      is_required = REQUIRED_MARKERS.any? { |marker| group_label.include?(marker) }

      # 同意系のチェックボックスは別処理なのでスキップ
      is_consent = CONSENT_PATTERNS.any? { |p| group_label.include?(p.downcase) }

      next unless is_required && !is_consent

      log "  必須チェックボックスグループ検出: #{group_label}"

      # 各選択肢のラベルを取得
      options = visible_boxes.map do |checkbox|
        label = get_checkbox_label(checkbox)
        { checkbox: checkbox, label: label }
      end

      # 避けるべきキーワードを含まない最初の選択肢を選ぶ
      selected = options.find do |opt|
        !RADIO_AVOID_PATTERNS.any? { |avoid| opt[:label].include?(avoid) }
      end

      # 見つからなければ最初の選択肢
      selected ||= options.first

      if selected
        begin
          driver.execute_script("arguments[0].click();", selected[:checkbox])
          log "  → チェックボックス選択: #{selected[:label]}"
        rescue StandardError => e
          log "  → チェックボックス選択失敗: #{e.message}"
        end
      end
    end
  end

  # チェックボックスグループのラベルを取得
  def get_checkbox_group_label(checkbox)
    # WPFormsの場合: チェックボックス専用のwpforms-field要素を探す
    begin
      # 最も近い wpforms-field-checkbox クラスを持つ要素を探す
      wpforms_field = checkbox.find_element(:xpath, 'ancestor::*[contains(@class, "wpforms-field-checkbox")]')
      label = wpforms_field.find_element(:css, '.wpforms-field-label')
      text = label.text.downcase
      return text if text.present?
    rescue Selenium::WebDriver::Error::NoSuchElementError
      # 見つからない場合は次の方法へ
    end

    # WPFormsの場合: 一般的なwpforms-field要素を探す（チェックボックス専用が見つからない場合）
    begin
      wpforms_field = checkbox.find_element(:xpath, 'ancestor::*[contains(@class, "wpforms-field")][1]')
      label = wpforms_field.find_element(:css, '.wpforms-field-label')
      text = label.text.downcase
      return text if text.present?
    rescue Selenium::WebDriver::Error::NoSuchElementError
      # 見つからない場合は次の方法へ
    end

    # fieldsetのlegendを探す
    begin
      fieldset = checkbox.find_element(:xpath, 'ancestor::fieldset')
      legend = fieldset.find_element(:css, 'legend')
      text = legend.text.downcase
      log "  [Debug] Fieldset legend found: #{text}"
      return text if text.present?
    rescue Selenium::WebDriver::Error::NoSuchElementError
      # 無視
    end

    # 親要素を遡ってラベルを探す
    begin
      parent = checkbox.find_element(:xpath, 'ancestor::*[contains(@class, "form-group") or contains(@class, "field")]')
      label = parent.find_element(:css, 'label, .label, dt, th')
      text = label.text.downcase
      log "  [Debug] Parent label found: #{text}"
      return text if text.present?
    rescue Selenium::WebDriver::Error::NoSuchElementError
      # 無視
    end

    # 親の親まで遡る
    begin
      grandparent = checkbox.find_element(:xpath, 'ancestor::*[3]')
      labels = grandparent.find_elements(:css, 'label, p, span')
      labels.each do |label|
        text = label.text.downcase
        if REQUIRED_MARKERS.any? { |marker| text.include?(marker) }
          log "  [Debug] Grandparent required label found: #{text}"
          return text
        end
      end
    rescue Selenium::WebDriver::Error::NoSuchElementError
      # 無視
    end

    # 前の要素を探す（より広く）
    begin
      cb_name = checkbox.attribute('name') rescue ''
      prev_elements = driver.find_elements(:xpath, "//input[@name='#{cb_name}']/preceding::*[self::label or self::p or self::span][position() <= 3]")
      prev_elements.each do |prev|
        text = prev.text.downcase
        if REQUIRED_MARKERS.any? { |marker| text.include?(marker) }
          log "  [Debug] Preceding required label found: #{text}"
          return text
        end
      end
    rescue Selenium::WebDriver::Error::NoSuchElementError
      # 無視
    end

    ''
  end

  # チェックボックス個別のラベルを取得
  def get_checkbox_label(checkbox)
    checkbox_id = checkbox.attribute('id')
    if checkbox_id.present?
      begin
        label = driver.find_element(:css, "label[for='#{checkbox_id}']")
        return label.text.downcase if label
      rescue Selenium::WebDriver::Error::NoSuchElementError
        # 無視
      end
    end

    # 親要素のテキスト
    begin
      parent = checkbox.find_element(:xpath, '..')
      return parent.text.downcase
    rescue Selenium::WebDriver::Error::NoSuchElementError
      # 無視
    end

    checkbox.attribute('value')&.downcase || ''
  end

  # 同意チェックボックスをチェック
  def check_consent_boxes
    checkboxes = driver.find_elements(:css, 'input[type="checkbox"]')
    checkboxes.each do |checkbox|
      next unless checkbox.displayed?
      next if checkbox.selected?  # 既にチェック済みならスキップ

      # チェックボックスの周辺テキストを取得
      name_attr = checkbox.attribute('name')&.downcase || ''
      id_attr = checkbox.attribute('id')&.downcase || ''
      label_text = get_label_text(checkbox)

      # 親要素のテキストも確認（2階層上まで探索）
      parent_text = ''
      begin
        parent = checkbox.find_element(:xpath, '..')
        parent_text = parent.text.downcase
        # 親のテキストで見つからない場合、さらに上の階層も確認
        if parent_text.blank? || !CONSENT_PATTERNS.any? { |p| parent_text.include?(p.downcase) }
          grandparent = checkbox.find_element(:xpath, 'ancestor::*[3]')
          gp_text = grandparent.text.downcase rescue ''
          parent_text = "#{parent_text} #{gp_text}" if gp_text.present?
        end
      rescue StandardError
        # 無視
      end

      # value属性もチェック（Salesforce等で同意テキストがvalueに含まれる場合）
      value_attr = checkbox.attribute('value')&.downcase || ''

      # 前後の兄弟要素のテキストも確認（Salesforce等でラベルが別要素の場合）
      sibling_text = ''
      begin
        siblings = checkbox.find_elements(:xpath, 'following-sibling::*[position() <= 2] | preceding-sibling::*[position() <= 2]')
        siblings.each do |sib|
          sib_text = sib.text.downcase rescue ''
          sibling_text = "#{sibling_text} #{sib_text}" if sib_text.present?
        end
      rescue StandardError
        # 無視
      end

      all_text = "#{name_attr} #{id_attr} #{label_text} #{parent_text} #{value_attr} #{sibling_text}".downcase

      # 同意系のキーワードが含まれていればチェック
      if CONSENT_PATTERNS.any? { |p| all_text.include?(p.downcase) }
        begin
          # スクロールしてから、JavaScriptでクリック（オーバーレイ回避）
          scroll_to_element(checkbox)
          sleep 0.3
          driver.execute_script("arguments[0].click();", checkbox)
          consent_label = label_text.to_s.strip.empty? ? name_attr : label_text
          log "  → 同意チェックボックスをチェック: #{consent_label}"
        rescue StandardError => e
          log "  → 同意チェックボックスのクリック失敗: #{e.message}"
        end
      end
    end

    # フォールバック: ページ内に同意キーワードがあり未チェックが1つだけの場合
    begin
      unchecked = checkboxes.select { |cb| cb.displayed? && !cb.selected? }
      if unchecked.size == 1
        page_text = driver.find_element(:css, 'body').text.downcase rescue ''
        if CONSENT_PATTERNS.any? { |p| page_text.include?(p.downcase) }
          cb = unchecked.first
          scroll_to_element(cb)
          sleep 0.3
          driver.execute_script("arguments[0].click();", cb)
          log "  → 同意チェックボックスをチェック（ページ内キーワード検出）"
        end
      end
    rescue StandardError => e
      log "  → 同意チェックボックスフォールバックエラー: #{e.message}"
    end
  end

  # フォーム入力後の同意チェックボックス再チェック（遅延読み込み・CSS非表示対策）
  def recheck_consent_boxes
    checkboxes = driver.find_elements(:css, 'input[type="checkbox"]')
    # displayed?がfalseでもCSS隠しチェックボックス（CF7等）があるため、selected?のみで判定
    unchecked = checkboxes.select { |cb| !cb.selected? }
    return if unchecked.empty?

    unchecked.each do |cb|
      name_attr = cb.attribute('name')&.downcase || ''
      label_text = get_label_text(cb)
      parent_text = ''
      begin
        # 3階層上までテキストを取得（CF7のネスト構造対策）
        parent = cb.find_element(:xpath, '..')
        parent_text = parent.text.downcase
        unless CONSENT_PATTERNS.any? { |p| parent_text.include?(p.downcase) }
          grandparent = cb.find_element(:xpath, 'ancestor::*[3]')
          gp_text = grandparent.text.downcase rescue ''
          parent_text = "#{parent_text} #{gp_text}"
        end
      rescue StandardError
      end

      all_text = "#{name_attr} #{label_text} #{parent_text}".downcase
      if CONSENT_PATTERNS.any? { |p| all_text.include?(p.downcase) }
        begin
          driver.execute_script("arguments[0].click();", cb)
          consent_label = label_text.to_s.strip.empty? ? name_attr : label_text
          log "  → 同意チェックボックスをチェック（入力後再検出）: #{consent_label}"
        rescue StandardError => e
          log "  → 同意チェックボックス再チェック失敗: #{e.message}"
        end
        return
      end
    end

    # フォールバック: 未チェックが1つでページに同意キーワードがあれば
    if unchecked.size == 1
      page_text = driver.find_element(:css, 'body').text.downcase rescue ''
      if CONSENT_PATTERNS.any? { |p| page_text.include?(p.downcase) }
        cb = unchecked.first
        begin
          driver.execute_script("arguments[0].click();", cb)
          log "  → 同意チェックボックスをチェック（入力後フォールバック）"
        rescue StandardError => e
          log "  → 同意チェックボックス入力後フォールバックエラー: #{e.message}"
        end
      end
    end
  rescue StandardError => e
    log "  → 同意再チェックエラー: #{e.message}"
  end

  # 送信ボタンをクリック
  def click_submit
    # type="submit"のボタンを検索（input[type="image"]も含む）
    begin
      submit_buttons = driver.find_elements(:css, "input[type='submit'], input[type='image'], button[type='submit'], button:not([type])")
      visible_buttons = submit_buttons.select(&:displayed?)

      # 戻るボタンを避けて送信ボタンを優先（確認画面対策）
      preferred = visible_buttons.sort_by do |btn|
        btn_text_raw = btn.text.to_s.strip
        btn_text = (btn_text_raw.empty? ? (btn.attribute('value') || '') : btn_text_raw).strip.downcase
        if btn_text.include?('戻') || btn_text.include?('back') || btn_text.include?('修正')
          2  # 戻るボタン: 低優先
        elsif btn_text.include?('送信') || btn_text.include?('submit') || btn_text.include?('send')
          0  # 送信ボタン: 高優先
        else
          1  # その他: 通常優先
        end
      end

      if preferred.any?
        btn = preferred.first
        btn_text_raw = btn.text.to_s.strip
        btn_text = btn_text_raw.empty? ? (btn.attribute('value') || '') : btn_text_raw
        log "送信ボタン発見: #{btn_text}"
        scroll_to_element(btn)
        sleep 0.5
        btn.click
        return true
      end
    rescue StandardError => e
      log "送信ボタン検索エラー: #{e.message}"
    end

    # テキストで検索
    SUBMIT_PATTERNS.each do |pattern|
      begin
        buttons = driver.find_elements(:xpath, "//*[contains(text(), '#{pattern}')] | //input[contains(@value, '#{pattern}')]")
        buttons.each do |btn|
          if btn.displayed? && %w[button input a span div].include?(btn.tag_name.downcase)
            log "送信ボタン発見（テキスト）: #{pattern}"
            scroll_to_element(btn)
            sleep 0.5
            btn.click
            return true
          end
        end
      rescue StandardError => e
        log "送信ボタン検索エラー（テキスト）: #{e.message}"
      end
    end

    # 最終手段: JavaScriptでフォーム送信を試みる
    begin
      forms = driver.find_elements(:css, 'form')
      forms.each do |form|
        next unless form.displayed?
        # フォーム内に入力欄があるか確認（フォームらしいものだけ対象）
        inputs = form.find_elements(:css, 'input:not([type="hidden"]), textarea')
        if inputs.size >= 2
          log "送信ボタン発見（JSフォールバック）: form.submit()"
          driver.execute_script("arguments[0].submit();", form)
          return true
        end
      end
    rescue StandardError => e
      log "JSフォーム送信エラー: #{e.message}"
    end

    false
  end

  # OKボタン/完了ボタンをクリック（戻るボタンは除外）
  def click_ok_button
    ok_patterns = %w[OK ok Ok 完了 finish done 確認しました 送信完了].freeze

    ok_patterns.each do |pattern|
      begin
        buttons = driver.find_elements(:xpath, "//button[contains(text(), '#{pattern}')] | //input[contains(@value, '#{pattern}')] | //a[contains(text(), '#{pattern}')]")
        buttons.each do |btn|
          if btn.displayed?
            log "OKボタン発見: #{pattern}"
            scroll_to_element(btn)
            sleep 0.3
            btn.click
            return true
          end
        end
      rescue StandardError => e
        log "OKボタン検索エラー: #{e.message}"
      end
    end

    false
  end

  # 要素までスクロール
  def scroll_to_element(element)
    driver.execute_script("arguments[0].scrollIntoView({block: 'center'});", element)
  end

  # 確認ダイアログを処理（複数回対応）
  def handle_alert
    max_attempts = 3
    attempts = 0

    while attempts < max_attempts
      sleep 1
      begin
        alert = driver.switch_to.alert
        alert_text = alert.text
        log "アラート検出: #{alert_text}"

        # エラー系のアラートかどうか判定
        if ALERT_ERROR_PATTERNS.any? { |p| alert_text.include?(p) }
          @alert_had_error = true
          log "  → バリデーションエラーのアラートを検出"
        end

        alert.accept
        log "アラート承認（#{attempts + 1}回目）"
        attempts += 1
      rescue Selenium::WebDriver::Error::NoSuchAlertError
        # アラートがなくなったら終了
        break
      end
    end
  end

  # 確認画面かどうかを判定
  def confirmation_page?
    page_source = driver.page_source

    # 送信ボタンの有無チェック
    has_submit_button = false
    begin
      submit_buttons = driver.find_elements(:css, "input[type='submit'], button[type='submit'], button:not([type])")
      has_submit_button = submit_buttons.any?(&:displayed?)
    rescue StandardError
      # 無視
    end

    return false unless has_submit_button

    # 入力欄の状態を一括チェック
    editable_count = 0
    visible_count = 0
    total_count = 0
    begin
      inputs = driver.find_elements(:css, 'input:not([type="hidden"]):not([type="submit"]):not([type="button"]):not([type="radio"]):not([type="checkbox"]), textarea')
      total_count = inputs.size
      inputs.each do |input|
        if input.displayed?
          visible_count += 1
          unless input.attribute('readonly').present? || input.attribute('disabled').present?
            editable_count += 1
          end
        end
      end
    rescue StandardError
      # 無視
    end

    # 確認画面のキーワード
    confirmation_keywords = [
      '確認画面', '入力内容の確認', '入力内容のご確認', '内容をご確認',
      '以下の内容で送信', '送信してよろしいですか', '入力内容確認',
      '以下の内容で宜しければ', '宜しければ', '以下の内容でよろしければ',
      'よろしければ送信', '内容で宜しければ', '内容でよろしければ',
      '確認してください', 'ご確認ください'
    ]
    has_confirmation_text = confirmation_keywords.any? { |keyword| page_source.include?(keyword) }

    # パターン1: 確認キーワード + 編集可能な入力欄が少ない
    if has_confirmation_text && editable_count < 3
      log "確認画面判定: true（キーワード + 編集可能#{editable_count}個）"
      return true
    end

    # 確認キーワードはあるが入力欄がまだ編集可能 = バリデーションエラーの可能性
    if has_confirmation_text && editable_count >= 3
      log "確認画面判定: false（キーワードあるが編集可能入力欄#{editable_count}個 = バリデーションエラーの可能性）"
      return false
    end

    # パターン2: 入力欄が消失 + 送信ボタンあり（キーワードなくても確認画面の可能性）
    if visible_count <= 1 && total_count >= 2
      log "確認画面判定: true（入力欄消失: 表示#{visible_count}/全#{total_count}）"
      return true
    end

    # パターン3: 入力欄の大半が非表示化（CF7確認アドオン）
    if total_count >= 3 && (total_count - visible_count) > visible_count
      hidden_count = total_count - visible_count
      log "確認画面判定: true（入力欄非表示化: 表示#{visible_count}/非表示#{hidden_count}）"
      return true
    end

    log "確認画面判定: false（キーワード: #{has_confirmation_text}, 編集可能: #{editable_count}, 表示: #{visible_count}）"
    false
  end

  # 送信成功を判定
  def check_success?
    # アラートでバリデーションエラーが検出されていた場合は失敗
    if @alert_had_error
      log "アラートエラー検出済みのため送信失敗と判定"
      return false
    end

    # AJAX送信の成功検出（CF7 / WPForms 等）
    return true if check_ajax_success?

    page_source = driver.page_source.downcase
    current_url = driver.current_url

    # 成功メッセージの検出（最優先）
    has_success_message = false
    SUCCESS_PATTERNS.each do |pattern|
      if page_source.include?(pattern.downcase)
        log "成功メッセージ検出: #{pattern}"
        has_success_message = true
        break
      end
    end
    return true if has_success_message

    # ページ内エラーチェック（URL変更があってもエラーなら失敗）
    has_page_error = false
    begin
      # 1. エラー用CSS要素の検出（表示されているもののみ）
      PAGE_ERROR_CSS.each do |selector|
        begin
          elements = driver.find_elements(:css, selector)
          visible_errors = elements.select { |el| el.displayed? && !el.text.strip.empty? }
          if visible_errors.any?
            error_text = visible_errors.first.text.strip[0..50]
            log "ページ内エラー要素検出: #{selector} → 「#{error_text}」"
            has_page_error = true
            break
          end
        rescue StandardError
        end
      end

      # 2. テキストパターンでの検出（CSS要素で見つからなかった場合）
      unless has_page_error
        body_text = driver.find_element(:css, 'body').text
        PAGE_ERROR_PATTERNS.each do |pattern|
          if body_text.include?(pattern)
            log "ページ内エラーテキスト検出: #{pattern}"
            has_page_error = true
            break
          end
        end
      end
    rescue StandardError
    end

    # URLが変わった場合（成功メッセージがなくても判定）
    if current_url != @customer.contact_url
      log "URL変更検出: #{current_url}"
      if has_page_error
        log "URL変更あるがページ内エラーメッセージ検出のため送信失敗と判定"
        return false
      end
      # URL変更 + フォーム入力欄が減っていれば成功とみなす
      begin
        remaining_inputs = driver.find_elements(:css, 'input:not([type="hidden"]):not([type="submit"]):not([type="button"]), textarea')
        visible_inputs = remaining_inputs.select(&:displayed?)
        if visible_inputs.size <= 2
          # 送信ボタンがまだある場合は確認画面の可能性
          submit_still_visible = false
          begin
            submit_buttons = driver.find_elements(:css, "input[type='submit'], button[type='submit']")
            submit_still_visible = submit_buttons.any?(&:displayed?)
          rescue StandardError
            # 無視
          end

          unless submit_still_visible
            log "URL変更 + フォーム消失（入力欄#{visible_inputs.size}個）: 成功と判定"
            return true
          else
            log "URL変更 + フォーム消失だが送信ボタンあり: 確認画面の可能性"
          end
        end
      rescue StandardError
        # エラー時はURL変更のみで判定
        return true
      end
      # フォームがまだ残っている場合でも、パスやクエリが変わっていれば成功
      begin
        orig_uri = URI.parse(@customer.contact_url) rescue nil
        curr_uri = URI.parse(current_url) rescue nil
        if orig_uri && curr_uri
          orig_path = orig_uri.path.chomp('/')
          curr_path = curr_uri.path.chomp('/')
          if orig_path != curr_path
            log "URL パス変更検出（#{orig_path} → #{curr_path}）: 成功と判定"
            return true
          end
          if orig_uri.query != curr_uri.query
            log "URL クエリ変更検出: 成功と判定"
            return true
          end
        end
      rescue StandardError
        # 無視
      end
      log "URL変更あり（プロトコル/フラグメントのみ）: 成功とみなさず"
    end

    # フォーム入力欄が消えた場合（送信完了でフォームが非表示になるパターン）
    begin
      remaining_inputs = driver.find_elements(:css, 'input:not([type="hidden"]):not([type="submit"]):not([type="button"]), textarea')
      visible_inputs = remaining_inputs.select(&:displayed?)
      if visible_inputs.size <= 1
        # 送信ボタンがまだある場合は確認画面の可能性（成功とみなさない）
        submit_still_visible = false
        begin
          submit_buttons = driver.find_elements(:css, "input[type='submit'], button[type='submit']")
          submit_still_visible = submit_buttons.any?(&:displayed?)
        rescue StandardError
          # 無視
        end

        if submit_still_visible
          log "入力欄消失だが送信ボタンあり: 確認画面の可能性（成功とみなさない）"
        else
          log "フォーム消失検出: 入力欄が#{visible_inputs.size}個に減少"
          return true
        end
      end
    rescue StandardError
      # 無視
    end

    false
  end

  # AJAX送信（CF7 / WPForms 等）の成功をDOM要素で判定
  def check_ajax_success?
    # --- Contact Form 7 ---
    begin
      # CF7 は送信成功時に .wpcf7 要素へ data-status="sent" を付与する
      # mail_sent_ng はフォーム送信成功だがメール配信失敗（サーバー側の問題）
      cf7_sent = driver.find_elements(:css, '.wpcf7[data-status="sent"], .wpcf7[data-status="mail_sent_ng"]')
      if cf7_sent.any?
        status = cf7_sent.first.attribute('data-status') rescue 'sent'
        log "AJAX成功検出: CF7 data-status=#{status}"
        return true
      end

      # CF7 は送信成功時に .wpcf7 に .sent クラスを追加する
      cf7_sent_class = driver.find_elements(:css, '.wpcf7.sent')
      if cf7_sent_class.any?
        log "AJAX成功検出: CF7 .wpcf7.sent クラス"
        return true
      end

      # 旧バージョンCF7 の成功メッセージ要素
      cf7_old = driver.find_elements(:css, '.wpcf7-mail-sent-ok')
      if cf7_old.any?(&:displayed?)
        log "AJAX成功検出: CF7 .wpcf7-mail-sent-ok（旧バージョン）"
        return true
      end

      # CF7 の応答出力欄（エラークラスがなく表示されていれば成功）
      cf7_response = driver.find_elements(:css, '.wpcf7-response-output')
      cf7_response.each do |el|
        next unless el.displayed?
        classes = el.attribute('class').to_s
        next if classes.include?('wpcf7-validation-errors') || classes.include?('wpcf7-acceptance-missing') || classes.include?('wpcf7-spam-blocked') || classes.include?('wpcf7-mail-sent-ng')
        text = el.text.to_s.strip
        next if text.length == 0
        # 失敗キーワードを含む場合は除外
        next if text.match?(/失敗|エラー|error|failed|問題があります|入力内容に問題|確認して再度/i)
        log "AJAX成功検出: CF7 .wpcf7-response-output（テキスト: #{text[0..50]}）"
        return true
      end
    rescue StandardError => e
      log "CF7判定中にエラー: #{e.message}"
    end

    # --- WPForms ---
    begin
      wpforms_confirm = driver.find_elements(:css, '.wpforms-confirmation-container')
      if wpforms_confirm.any?(&:displayed?)
        log "AJAX成功検出: WPForms .wpforms-confirmation-container"
        return true
      end
    rescue StandardError => e
      log "WPForms判定中にエラー: #{e.message}"
    end

    false
  end
end
