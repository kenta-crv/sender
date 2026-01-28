# frozen_string_literal: true

require 'sqlite3'
require 'webdrivers'
require_relative 'app/services/form_sender'

# 顧客情報を取得するシンプルな構造体
Customer = Struct.new(:id, :company, :contact_url)

# DBから顧客情報を取得
def get_customer(id)
  db = SQLite3::Database.new('db/development.sqlite3')
  row = db.execute('SELECT id, company, contact_url FROM customers WHERE id = ?', id).first
  return nil unless row
  Customer.new(row[0], row[1], row[2])
end

# メイン処理
customer_id = ARGV[0]&.to_i || 6
customer = get_customer(customer_id)

unless customer
  puts "顧客ID #{customer_id} が見つかりません"
  exit 1
end

puts "企業: #{customer.company}"
puts "URL: #{customer.contact_url}"
puts

# blank?メソッドを追加（Rails無しで動作させるため）
class NilClass
  def blank?
    true
  end
end

class String
  def blank?
    empty?
  end

  def present?
    !blank?
  end
end

class Object
  def present?
    respond_to?(:empty?) ? !empty? : !nil?
  end

  def blank?
    respond_to?(:empty?) ? empty? : !self
  end
end

# FormSenderを実行
sender = FormSender.new(debug: true, confirm_mode: true)
result = sender.send_to_customer(customer)

puts
puts '=== 結果 ==='
puts "企業名: #{customer.company}"
puts "URL: #{customer.contact_url}"
puts "ステータス: #{result[:status]}"
puts "メッセージ: #{result[:message]}"
