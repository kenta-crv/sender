# frozen_string_literal: true

namespace :sender do
  desc 'テスト送信（1件のみ）'
  task test: :environment do
    # contact_urlが設定されている最初の顧客を取得
    customer = Customer.where.not(contact_url: [nil, '']).first

    if customer.nil?
      puts 'contact_urlが設定されている顧客が見つかりません'
      exit
    end

    puts "===== テスト送信開始 ====="
    puts "会社名: #{customer.company}"
    puts "URL: #{customer.contact_url}"
    puts "========================="

    sender = FormSender.new(debug: true)
    result = sender.send_to_customer(customer)

    puts ""
    puts "===== 結果 ====="
    puts "ステータス: #{result[:status]}"
    puts "メッセージ: #{result[:message]}"
    puts "================"
  end

  desc '指定したcustomer_idに送信'
  task :send, [:customer_id] => :environment do |_t, args|
    customer = Customer.find_by(id: args[:customer_id])

    if customer.nil?
      puts "Customer ID #{args[:customer_id]} が見つかりません"
      exit
    end

    puts "===== 送信開始 ====="
    puts "会社名: #{customer.company}"
    puts "URL: #{customer.contact_url}"
    puts "===================="

    sender = FormSender.new(debug: true)
    result = sender.send_to_customer(customer)

    puts ""
    puts "===== 結果 ====="
    puts "ステータス: #{result[:status]}"
    puts "メッセージ: #{result[:message]}"
    puts "================"

    # Callモデルに記録
    Call.create!(
      customer: customer,
      status: result[:status],
      comment: result[:message]
    )
    puts "Callモデルに記録しました"
  end
end
