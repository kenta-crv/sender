# frozen_string_literal: true
$stdout.sync = true
$stderr.sync = true

# ContactUrlDetector 目視確認スクリプト
# ブラウザが表示された状態で動作を確認できます
#
# 使い方:
#   ruby test_detector_visual.rb                    # デフォルト5件テスト
#   ruby test_detector_visual.rb https://example.com  # 指定URLをテスト

require 'selenium-webdriver'
require 'webdrivers'
require 'uri'
require 'set'

# ActiveSupport 互換メソッド
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

# NGブラックリスト読み込み
require_relative 'config/initializers/blocked_urls'

module Rails
  def self.logger
    @l ||= Object.new.tap { |l|
      def l.info(m); end
      def l.error(m); end
    }
  end
end

require_relative 'app/services/contact_url_detector'
Customer = Struct.new(:company, :url, :contact_url, keyword_init: true)

# === テスト対象 ===
if ARGV[0]
  # コマンドライン引数でURL指定
  test_cases = [
    { company: '指定URL', url: ARGV[0] }
  ]
else
  # デフォルト5件
  test_cases = [
    { company: 'ラクス', url: 'https://www.rakus.co.jp/' },
    { company: 'Chatwork', url: 'https://corp.chatwork.com/' },
    { company: 'freee', url: 'https://www.freee.co.jp/' },
    { company: 'マネーフォワード', url: 'https://corp.moneyforward.com/' },
    { company: 'Sansan', url: 'https://jp.sansan.com/' },
  ]
end

puts "=" * 60
puts "ContactUrlDetector 目視確認テスト（ブラウザ表示モード）"
puts "NGブラックリスト: #{BLOCKED_URL_PATTERNS.size}件登録済み"
puts "=" * 60
puts

# headless: false でブラウザを表示
detector = ContactUrlDetector.new(debug: true, headless: false)
results = []

test_cases.each_with_index do |tc, i|
  puts "-" * 60
  puts "#{i + 1}/#{test_cases.size}: #{tc[:company]}"
  puts "HP URL: #{tc[:url]}"
  puts "-" * 60

  customer = Customer.new(company: tc[:company], url: tc[:url], contact_url: nil)

  start_time = Time.now
  result = detector.detect(customer)
  elapsed = (Time.now - start_time).round(1)

  results << result.merge(company: tc[:company], url: tc[:url], elapsed: elapsed)

  puts
  puts "  結果: #{result[:status]}"
  puts "  検出URL: #{result[:contact_url] || '(なし)'}"
  puts "  メッセージ: #{result[:message]}"
  puts "  所要時間: #{elapsed}秒"

  if result[:status] == 'detected'
    puts
    puts "  >>> ブラウザで検出されたページを確認してください <<<"
    puts "  >>> Enterキーで次へ進みます <<<"
    $stdin.gets
  end
  puts
end

# サマリー
puts "=" * 60
puts "テスト結果サマリー"
puts "=" * 60
puts

detected = results.select { |r| r[:status] == 'detected' }
puts "検出成功: #{detected.size}/#{results.size}件"
puts

results.each do |r|
  status_mark = r[:status] == 'detected' ? '[OK]' : '[NG]'
  puts "#{status_mark} #{r[:company]}"
  puts "     HP: #{r[:url]}"
  puts "     検出: #{r[:contact_url] || '未検出'}"
  puts "     (#{r[:elapsed]}秒)"
  puts
end
