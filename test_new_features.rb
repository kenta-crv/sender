# frozen_string_literal: true

$stdout.sync = true

require 'sqlite3'
require 'webdrivers'
require_relative 'app/services/form_sender'

# blank?/present?メソッド追加（Rails無しで動作させるため）
class NilClass
  def blank? = true
  def present? = false
end

class String
  def blank? = empty?
  def present? = !blank?
  def presence = blank? ? nil : self
end

class Object
  def present? = respond_to?(:empty?) ? !empty? : !nil?
  def blank? = respond_to?(:empty?) ? empty? : !self
end

Customer = Struct.new(:id, :company, :contact_url)

db = SQLite3::Database.new('db/development.sqlite3')

mode = ARGV[0] || 'sample'

if mode == 'all'
  # 全件テスト
  rows = db.execute('SELECT id, company, contact_url FROM customers WHERE contact_url IS NOT NULL AND contact_url != "" ORDER BY id')
else
  # サンプルテスト（数件）
  ids = ARGV.map(&:to_i).reject(&:zero?)
  ids = [1, 5, 9, 37, 84] if ids.empty?
  rows = ids.map { |id| db.execute('SELECT id, company, contact_url FROM customers WHERE id = ?', id).first }.compact
end

total = rows.size
results = { '送信成功' => [], '送信失敗' => [], 'フォーム未検出' => [], 'アクセス失敗' => [], '営業禁止' => [], 'エラー' => [] }

puts "=" * 60
puts "テスト開始: #{total}件"
puts "=" * 60

rows.each_with_index do |row, idx|
  customer = Customer.new(row[0], row[1], row[2])
  puts "\n[#{idx + 1}/#{total}] ID:#{customer.id} #{customer.company}"
  puts "  URL: #{customer.contact_url}"

  sender = FormSender.new(debug: true, confirm_mode: false)
  result = sender.send_to_customer(customer)

  status = result[:status]
  results[status] ||= []
  results[status] << customer.id

  puts "  結果: #{status} - #{result[:message]}"
end

puts "\n" + "=" * 60
puts "テスト結果サマリー"
puts "=" * 60
results.each do |status, ids|
  next if ids.empty?
  puts "#{status}: #{ids.size}件 #{ids.inspect}"
end

success = results['送信成功'].size
no_sales = results['営業禁止'].size
total_valid = total - results['アクセス失敗'].size - results['フォーム未検出'].size - no_sales
puts "\n送信成功: #{success}/#{total}件"
puts "営業禁止スキップ: #{no_sales}件" if no_sales > 0
puts "成功率（有効フォーム対象）: #{total_valid > 0 ? (success.to_f / total_valid * 100).round(1) : 0}%"
