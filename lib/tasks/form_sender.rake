# frozen_string_literal: true

namespace :form do
  desc '指定したcustomer_idのフォームに送信（確認モード）'
  task :send, [:customer_id] => :environment do |_t, args|
    customer_id = args[:customer_id]&.to_i

    if customer_id.nil? || customer_id.zero?
      puts 'Usage: rails form:send[customer_id]'
      puts 'Example: rails form:send[6]'
      exit 1
    end

    customer = Customer.find_by(id: customer_id)
    unless customer
      puts "Customer ID #{customer_id} が見つかりません"
      exit 1
    end

    puts "企業: #{customer.company}"
    puts "URL: #{customer.contact_url}"
    puts

    sender = FormSender.new(debug: true, confirm_mode: true, save_to_db: true)
    result = sender.send_to_customer(customer)

    puts
    puts '=== 結果 ==='
    puts "ステータス: #{result[:status]}"
    puts "メッセージ: #{result[:message]}"
  end

  desc '指定したcustomer_idのフォームに送信（自動送信モード）'
  task :send_auto, [:customer_id] => :environment do |_t, args|
    customer_id = args[:customer_id]&.to_i

    if customer_id.nil? || customer_id.zero?
      puts 'Usage: rails form:send_auto[customer_id]'
      puts 'Example: rails form:send_auto[6]'
      exit 1
    end

    customer = Customer.find_by(id: customer_id)
    unless customer
      puts "Customer ID #{customer_id} が見つかりません"
      exit 1
    end

    puts "企業: #{customer.company}"
    puts "URL: #{customer.contact_url}"
    puts

    sender = FormSender.new(debug: true, confirm_mode: false, save_to_db: true)
    result = sender.send_to_customer(customer)

    puts
    puts '=== 結果 ==='
    puts "ステータス: #{result[:status]}"
    puts "メッセージ: #{result[:message]}"
  end

  desc '送信履歴を表示'
  task history: :environment do
    calls = Call.includes(:customer)
                .where("comment LIKE '%フォーム送信%'")
                .order(created_at: :desc)
                .limit(20)

    if calls.empty?
      puts '送信履歴がありません'
      exit 0
    end

    puts '=== 送信履歴（直近20件）==='
    puts
    calls.each do |call|
      company = call.customer&.company || '不明'
      puts "#{call.created_at.strftime('%Y-%m-%d %H:%M')} | #{company} | #{call.status}"
      puts "  #{call.comment}"
      puts
    end
  end

  desc 'contact_urlがある全企業に連続送信（確認モード）'
  task send_all: :environment do
    customers = Customer.where.not(contact_url: [nil, ''])
    total = customers.count

    puts "送信対象: #{total}件"
    puts '続行しますか？ (y/n)'

    input = $stdin.gets.chomp
    unless input.downcase == 'y'
      puts 'キャンセルしました'
      exit 0
    end

    success_count = 0
    fail_count = 0

    customers.each_with_index do |customer, index|
      puts
      puts "=== #{index + 1}/#{total}: #{customer.company} ==="

      sender = FormSender.new(debug: true, confirm_mode: true, save_to_db: true)
      result = sender.send_to_customer(customer)

      if result[:status] == '送信成功' || result[:status] == '確認完了'
        success_count += 1
      else
        fail_count += 1
      end

      puts "結果: #{result[:status]}"
    end

    puts
    puts '=== 送信完了 ==='
    puts "成功: #{success_count}件"
    puts "失敗: #{fail_count}件"
    puts "成功率: #{(success_count.to_f / total * 100).round(1)}%"
  end
end
