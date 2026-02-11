# frozen_string_literal: true
$stdout.sync = true
$stderr.sync = true

# =============================================================
# フェーズ5 テスト2: FormSender 送信テスト
# =============================================================
# 実際にフォーム送信が正しく動作するかを確認
# confirm_mode: true → 送信前にブラウザで目視確認、手動で送信可否を判断
# headless: false → ブラウザ表示あり
#
# 使い方:
#   ruby test_form_sender.rb                    # DBからcontact_url設定済み3件をテスト
#   ruby test_form_sender.rb URL                # 指定URLをテスト
#   ruby test_form_sender.rb --auto-detect      # contact_url未設定→自動検出→送信テスト
#   ruby test_form_sender.rb --blacklist        # NGブラックリスト該当URLテスト
#
# 確認項目:
#   - フォームへの自動入力が正しく行われるか
#   - 営業禁止ワード検出が動作するか
#   - 送信成功判定が正しいか
#   - 確認画面→送信の2段階が動作するか
#
# 注意: confirm_mode=true なので自動送信はされません。
#       ブラウザで確認後、送信する場合は手動で送信ボタンをクリックしてください。

require 'selenium-webdriver'
require 'uri'
require 'set'
require 'net/http'
require 'openssl'
require 'sqlite3'

# --- Rails互換パッチ ---
class Object
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end
  def present?
    !blank?
  end
end
class NilClass; def blank?; true; end; end
class String; def blank?; strip.empty?; end; end

module Rails
  def self.logger
    @logger ||= Object.new.tap do |l|
      def l.info(msg); end
      def l.error(msg); end
    end
  end
end

# NGブラックリスト・サービス読み込み
require_relative 'config/initializers/blocked_urls'
require_relative 'app/services/contact_url_detector'
require_relative 'app/services/form_sender'

# ファイルベース待機（stdinが使えない環境用）
SIGNAL_FILE = File.join(__dir__, '.continue').encode('UTF-8')

def wait_for_signal(message = "waiting for confirmation")
  # 前回のシグナルファイルが残っていたら削除
  File.delete(SIGNAL_FILE) if File.exist?(SIGNAL_FILE)

  $stdout.puts ""
  $stdout.puts "=" * 50
  $stdout.puts " [WAITING] #{message}"
  $stdout.puts "=" * 50
  $stdout.puts ""
  $stdout.puts "  sender-master/.continue to continue"
  $stdout.puts ""
  $stdout.puts "  waiting..."

  loop do
    if File.exist?(SIGNAL_FILE)
      File.delete(SIGNAL_FILE)
      $stdout.puts "  -> signal detected, continuing"
      break
    end
    sleep 2
  end
end

# confirm_callback: FormSender内の確認待ちで使用
CONFIRM_CALLBACK = -> { wait_for_signal("check form input in browser") }

# 顧客ダミー構造体（update_column互換メソッド付き）
CustomerRecord = Struct.new(:id, :company, :url, :contact_url, :contact_form, keyword_init: true) do
  def update_column(attr, value)
    self[attr] = value
    puts "[DB模擬] customer.#{attr} = #{value}"
  end
end

# =============================================================
# テストモード判定
# =============================================================
mode = :normal
target_url = nil
send_mode = ARGV.include?('--send')
filtered_argv = ARGV.reject { |a| a == '--send' }

if filtered_argv[0] == '--auto-detect'
  mode = :auto_detect
elsif filtered_argv[0] == '--blacklist'
  mode = :blacklist
elsif filtered_argv[0] && !filtered_argv[0].start_with?('--')
  mode = :single_url
  target_url = filtered_argv[0]
end

confirm = !send_mode

puts "=" * 70
puts " FormSender 送信テスト（フェーズ5）"
puts "=" * 70
puts
puts "モード:          #{mode}"
puts "confirm_mode:    #{confirm}#{send_mode ? '（自動送信モード）' : '（送信前にブラウザで確認）'}"
puts "headless:        false（ブラウザ表示あり）"
puts "save_to_db:      false（DB保存なし、安全）"
puts

# =============================================================
# テストケース準備
# =============================================================
test_cases = []

case mode
when :single_url
  # 指定URLをテスト
  test_cases << {
    label: '指定URL',
    customer: CustomerRecord.new(
      id: 0,
      company: 'テスト企業',
      url: target_url,
      contact_url: target_url,
      contact_form: nil
    )
  }

when :blacklist
  # NGブラックリスト該当URLテスト
  test_cases << {
    label: 'NGブラックリスト該当URL',
    customer: CustomerRecord.new(
      id: 0,
      company: 'NG企業（Indeed）',
      url: 'https://jp.indeed.com/',
      contact_url: 'https://jp.indeed.com/contact',
      contact_form: nil
    ),
    expect_status: 'NG対象'
  }

when :auto_detect
  # contact_url未設定 → 自動検出テスト
  # DBからURLのみ設定済みの顧客を1件取得（contact_urlをクリアしてテスト）
  db_path = File.expand_path('../../0124 追加バイナリ/development.sqlite3', __FILE__)
  db = SQLite3::Database.new(db_path)
  db.results_as_hash = true

  row = db.execute(
    "SELECT id, company, url, contact_url FROM customers WHERE url IS NOT NULL AND url != '' AND contact_url IS NOT NULL AND contact_url != '' LIMIT 1"
  ).first

  if row
    test_cases << {
      label: '自動検出→送信テスト',
      customer: CustomerRecord.new(
        id: row['id'],
        company: row['company'],
        url: row['url'],
        contact_url: nil,  # 未設定にして自動検出をトリガー
        contact_form: nil
      ),
      note: "元のcontact_url: #{row['contact_url']}"
    }
  end
  db.close

when :normal
  # DBからcontact_url設定済みの顧客を3件取得
  db_path = File.expand_path('../../0124 追加バイナリ/development.sqlite3', __FILE__)
  db = SQLite3::Database.new(db_path)
  db.results_as_hash = true

  rows = db.execute(
    "SELECT id, company, url, contact_url FROM customers WHERE contact_url IS NOT NULL AND contact_url != '' ORDER BY RANDOM() LIMIT 5"
  )

  rows.each do |row|
    test_cases << {
      label: "DB顧客テスト",
      customer: CustomerRecord.new(
        id: row['id'],
        company: row['company'],
        url: row['url'],
        contact_url: row['contact_url'],
        contact_form: nil
      )
    }
  end
  db.close
end

if test_cases.empty?
  puts "[ERROR] テストケースがありません"
  exit 1
end

puts "テスト件数: #{test_cases.size}件"
puts

# =============================================================
# テスト実行
# =============================================================
results = []
total_start = Time.now

test_cases.each_with_index do |tc, i|
  cust = tc[:customer]

  puts "=" * 70
  puts "テスト #{i + 1}/#{test_cases.size}: #{tc[:label]}"
  puts "=" * 70
  puts "  会社名:      #{cust.company} (ID: #{cust.id})"
  puts "  HP URL:      #{cust.url}"
  puts "  contact_url: #{cust.contact_url || '(未設定 → 自動検出)'}"
  puts "  備考:        #{tc[:note]}" if tc[:note]
  puts

  start_time = Time.now

  begin
    sender = FormSender.new(
      debug: true,
      confirm_mode: confirm,
      save_to_db: false,
      headless: false,
      confirm_callback: confirm ? CONFIRM_CALLBACK : nil
    )
    result = sender.send_to_customer(cust)
  rescue => e
    result = { status: 'エラー', message: "例外: #{e.message}" }
  end

  elapsed = (Time.now - start_time).round(1)

  results << {
    company: cust.company,
    id: cust.id,
    contact_url: cust.contact_url,
    status: result[:status],
    message: result[:message],
    elapsed: elapsed,
    label: tc[:label],
    expect_status: tc[:expect_status]
  }

  # 期待ステータスとの比較（--blacklist等）
  status_match = if tc[:expect_status]
                   result[:status] == tc[:expect_status] ? 'PASS' : 'FAIL'
                 else
                   nil
                 end

  puts
  puts "  結果:        #{result[:status]}"
  puts "  メッセージ:  #{result[:message]}"
  puts "  所要時間:    #{elapsed}秒"
  puts "  期待判定:    #{status_match}" if status_match
  puts

  # 次のテストとの間に待機
  if i < test_cases.size - 1
    wait_for_signal("next test")
  end
end

total_elapsed = (Time.now - total_start).round(1)

# =============================================================
# テスト結果サマリー
# =============================================================
puts
puts "=" * 70
puts " FormSender テスト結果サマリー"
puts "=" * 70
puts

results.each_with_index do |r, i|
  status_icon = case r[:status]
                when '確認完了' then '[OK]'
                when '自動送信成功' then '[OK]'
                when 'NG対象' then '[NG]'
                when '営業禁止' then '[SKIP]'
                when 'フォーム未検出' then '[MISS]'
                else '[FAIL]'
                end

  puts "#{i + 1}. #{status_icon} #{r[:company]} (ID: #{r[:id]})"
  puts "   ステータス: #{r[:status]}"
  puts "   メッセージ: #{r[:message]}"
  puts "   contact_url: #{r[:contact_url] || '(自動検出)'}"
  puts "   所要時間:   #{r[:elapsed]}秒"
  if r[:expect_status]
    match = r[:status] == r[:expect_status]
    puts "   期待判定:   #{match ? 'PASS' : 'FAIL'} (期待: #{r[:expect_status]}, 実際: #{r[:status]})"
  end
  puts
end

# 統計
puts "-" * 70
puts " 統計"
puts "-" * 70
status_counts = results.group_by { |r| r[:status] }.transform_values(&:size)
status_counts.each do |status, count|
  puts "  #{status}: #{count}件"
end
puts
puts "  合計時間:    #{total_elapsed}秒"
avg = (results.map { |r| r[:elapsed] }.sum / results.size).round(1)
puts "  平均時間:    #{avg}秒/件"
puts "  目標:        30〜60秒/件"
puts

puts "テスト完了。"
