# rails runner import_csv.rb /home/smart/webroot/okurite/kaigo_production.csv
# rails runner import_csv.rb /Users/okuyamakenta/program/okurite/kaigo_production.csv

require 'csv'
require 'sqlite3'
require 'set'

csv_path = ARGV[0] || 'kaigo_production.csv'

unless File.exist?(csv_path)
  puts "CSVファイルが見つかりません: #{csv_path}"
  exit 1
end

db = SQLite3::Database.new('db/development.sqlite3')

# 既存の会社名をセットに格納
existing = Set.new(
  db.execute("SELECT company FROM customers").flatten.map(&:to_s)
)

imported = 0
updated  = 0
skipped_no_change = 0

# BOM付きUTF-8への対応を追加
CSV.foreach(csv_path, headers: true, encoding: 'BOM|UTF-8', liberal_parsing: true) do |row|
  # ヘッダー名が不一致でも、位置（インデックス）で補完するロジックを追加
  company     = (row['company'] || row[0]).to_s.strip
  
  # companyが空ならスキップ
  next if company.empty?

  tel         = (row['tel']     || row[1]).to_s.strip
  address     = (row['address'] || row[2]).to_s.strip
  url         = (row['url']     || row[3]).to_s.strip
  contact_url = (row['url_2']   || row[4]).to_s.strip

  # 固定値にする
  business = "介護事業所"

  attempts = 0

  begin
    now = Time.now.strftime("%Y-%m-%d %H:%M:%S")

    if existing.include?(company)
      # 既存レコードがある場合は内容を比較して更新
      current_values = db.execute(
        "SELECT tel, url, address, contact_url, business FROM customers WHERE company = ?",
        [company]
      ).first

      current_values ||= []
      new_values = [tel, url, address, contact_url, business]

      if current_values.map(&:to_s) != new_values.map(&:to_s)
        db.execute(
          "UPDATE customers SET 
            tel = ?, url = ?, address = ?, contact_url = ?, business = ?, updated_at = ?
           WHERE company = ?",
          [tel, url, address, contact_url, business, now, company]
        )
        updated += 1
        puts "更新完了: #{company}"
      else
        skipped_no_change += 1
      end
    else
      # 新規挿入
      db.execute(
        "INSERT INTO customers
        (company, tel, url, address, contact_url, business, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
        [company, tel, url, address, contact_url, business, now, now]
      )
      imported += 1
      existing << company
      puts "新規登録: #{company}"
    end

  rescue SQLite3::BusyException
    attempts += 1
    if attempts <= 5
      sleep 0.1
      retry
    else
      puts "ロックで挿入/更新失敗: #{company}"
    end
  end
end

puts ""
puts "=== インポート結果 ==="
puts "新規登録: #{imported}件"
puts "データ更新: #{updated}件"
puts "変更なしスキップ: #{skipped_no_change}件"

total = db.execute("SELECT COUNT(*) FROM customers").first.first

puts ""
puts "=== DB状況 ==="
puts "全顧客数: #{total}件"