#!/usr/bin/env ruby
require 'csv'
require 'sqlite3'
require 'set'

csv_path = ARGV[0] || 'C:/Users/mhero/OneDrive/デスクトップ/お問い合わせフォーム/案件内容(時系列)/9 追加データ.csv'

unless File.exist?(csv_path)
  puts "CSVファイルが見つかりません: #{csv_path}"
  exit 1
end

db = SQLite3::Database.new('db/development.sqlite3')

existing = Set.new(db.execute("SELECT company FROM customers").flatten.map(&:to_s))

imported = 0
skipped_blank = 0
skipped_dup = 0
skipped_no_url = 0
now = Time.now.strftime('%Y-%m-%d %H:%M:%S')

CSV.foreach(csv_path, headers: true, encoding: 'UTF-8') do |row|
  company     = row['company'].to_s.strip
  tel         = row['tel'].to_s.strip
  url         = row['url'].to_s.strip
  address     = row['address'].to_s.strip
  email       = row['email'].to_s.strip
  contact_url = row['contact_url'].to_s.strip

  if company.empty?
    skipped_blank += 1
    next
  end

  if existing.include?(company)
    skipped_dup += 1
    puts "  重複スキップ: #{company}"
    next
  end

  if contact_url.empty? || !contact_url.start_with?('http')
    skipped_no_url += 1
    puts "  contact_url無し: #{company} (#{contact_url})"
    next
  end

  # --- 行単位トランザクション + リトライ ---
  attempts = 0
  begin
    db.transaction do
      db.execute(
        "INSERT INTO customers (company, tel, url, address, email, contact_url, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        [company, tel, url, address, email, contact_url, now, now]
      )
    end
    imported += 1
    existing << company
  rescue SQLite3::BusyException
    attempts += 1
    if attempts <= 5
      sleep 0.1  # 100ms 待って再試行
      retry
    else
      puts "  ロックで挿入失敗: #{company}"
    end
  end
end

puts ""
puts "=== インポート結果 ==="
puts "インポート成功: #{imported}件"
puts "空行スキップ: #{skipped_blank}件"
puts "重複スキップ: #{skipped_dup}件"
puts "contact_url無しスキップ: #{skipped_no_url}件"

total = db.execute("SELECT COUNT(*) FROM customers").first.first
with_url = db.execute("SELECT COUNT(*) FROM customers WHERE contact_url IS NOT NULL AND contact_url != ''").first.first
puts ""
puts "=== DB状況 ==="
puts "全顧客数: #{total}件"
puts "contact_urlあり: #{with_url}件"