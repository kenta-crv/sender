# frozen_string_literal: true
$stdout.sync = true
$stderr.sync = true

# ContactUrlDetector スタンドアロンテスト
# 使い方: ruby test_detector.rb
# Rails不要、selenium-webdriver と webdrivers gem のみ必要

require 'selenium-webdriver'
require 'webdrivers'
require 'uri'
require 'set'
require 'net/http'
require 'openssl'

# NGブラックリスト読み込み
require_relative 'config/initializers/blocked_urls'

# Rails未使用のため ActiveSupport 互換メソッド定義
class Object
  def blank?
    respond_to?(:empty?) ? empty? : !self
  end
  def present?
    !blank?
  end
end

class NilClass
  def blank?; true; end
end

class String
  def blank?
    strip.empty?
  end
end

module Rails
  def self.logger
    @logger ||= Object.new.tap do |l|
      def l.info(msg); end
      def l.error(msg); end
    end
  end
end

# ContactUrlDetector を直接読み込み
require_relative 'app/services/contact_url_detector'

# テスト用の顧客ダミー
Customer = Struct.new(:company, :url, :contact_url, keyword_init: true)

# ===== テスト対象URL =====
# 実在する企業HPを5件テスト（フォームがありそうなサイト）
test_cases = [
  { company: 'テスト企業1（ラクス）', url: 'https://www.rakus.co.jp/' },
  { company: 'テスト企業2（Chatwork）', url: 'https://corp.chatwork.com/' },
  { company: 'テスト企業3（freee）', url: 'https://www.freee.co.jp/' },
  { company: 'テスト企業4（マネーフォワード）', url: 'https://corp.moneyforward.com/' },
  { company: 'テスト企業5（Sansan）', url: 'https://jp.sansan.com/' },
]

puts "=" * 60
puts "ContactUrlDetector スタンドアロンテスト"
puts "=" * 60
puts

detector = ContactUrlDetector.new(debug: true, headless: true)
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
  puts
end

# サマリー表示
puts "=" * 60
puts "テスト結果サマリー"
puts "=" * 60
puts

detected = results.select { |r| r[:status] == 'detected' }
not_detected = results.select { |r| r[:status] == 'not_detected' }

puts "検出成功: #{detected.size}/#{results.size}件"
puts "検出失敗: #{not_detected.size}/#{results.size}件"
puts

results.each do |r|
  status_mark = r[:status] == 'detected' ? '[OK]' : '[NG]'
  puts "#{status_mark} #{r[:company]}"
  puts "     HP: #{r[:url]}"
  puts "     検出: #{r[:contact_url] || '未検出'}"
  puts "     (#{r[:elapsed]}秒)"
  puts
end
