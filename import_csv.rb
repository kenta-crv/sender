#rails runner import_csv.rb /home/smart/webroot/okurite/factory.csv

require 'csv'
require 'sqlite3'
require 'set'

csv_path = ARGV[0] || 'factory.csv'

unless File.exist?(csv_path)
  puts "CSVファイルが見つかりません: #{csv_path}"
  exit 1
end

db = SQLite3::Database.new('db/development.sqlite3')

# 既存企業名セット（重複チェック用）
existing = Set.new(db.execute("SELECT company FROM customers").flatten.map(&:to_s))

imported = 0
skipped_blank = 0
skipped_dup = 0
now = Time.zone # Rails タイムゾーン対応

CSV.foreach(csv_path, headers: true, encoding: 'UTF-8') do |row|
  company     = row['company'].to_s.strip
  tel         = row['tel'].to_s.strip
  url         = row['url'].to_s.strip
  address     = row['address'].to_s.strip
  email       = row['email'].to_s.strip
  contact_url = row['contact_url'].to_s.strip
  business    = row['business'].to_s.strip

  # 空行スキップ（会社名がない場合のみ）
  if company.empty?
    skipped_blank += 1
    next
  end

  # 重複チェック
  if existing.include?(company)
    skipped_dup += 1
    puts "  重複スキップ: #{company}"
    next
  end

  # --- contact_url の空チェックは削除 ---
  # 空でも登録される

  attempts = 0
  begin
    db.transaction do
      db.execute(
        "INSERT INTO customers (company, tel, url, address, email, contact_url, business, created_at, updated_at)
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [company, tel, url, address, email, contact_url, business, now, now]
      )
    end
    imported += 1
    existing << company
  rescue SQLite3::BusyException
    attempts += 1
    if attempts <= 5
      sleep 0.1
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

total = db.execute("SELECT COUNT(*) FROM customers").first.first
puts ""
puts "=== DB状況 ==="
puts "全顧客数: #{total}件"