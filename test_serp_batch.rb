# test_serp_batch.rb（プロジェクトルートに配置）
# 実行: bundle exec rails runner test_serp_batch.rb

puts "=== SERP API バッチテスト ==="

# 1. 接続テスト
client = BrightData::SerpClient.new
puts "\n--- 単一リクエストテスト ---"
result = client.search(query: "株式会社テスト 東京 IT")
puts "Top-level keys: #{result.keys}"

if result["organic_results"]
  puts "organic_results: #{result["organic_results"].size}件"
  result["organic_results"].first(3).each do |r|
    puts "  title: #{r["title"]}"
    puts "  link:  #{r["link"]}"
  end
elsif result["organic"]
  puts "organic: #{result["organic"].size}件"
  result["organic"].first(3).each do |r|
    puts "  title: #{r["title"]}"
    puts "  link:  #{r["link"]}"
  end
else
  puts "WARNING: organic結果キーが不明。全キー: #{result.keys}"
  puts "レスポンス先頭500文字:"
  puts JSON.generate(result).first(500)
end

# 2. バッチテスト（3件）
puts "\n--- バッチテスト ---"
test_queries = ["東京 Web制作会社", "大阪 システム開発", "福岡 IT企業"]
batch = client.batch_search(test_queries, delay_between: 2)

batch.each do |b|
  has_error = b["result"]["error"]
  organic_count = b["result"]["organic_results"]&.size || b["result"]["organic"]&.size || 0
  status = has_error ? "ERROR: #{has_error}" : "OK (#{organic_count} results)"
  puts "  #{b["query"]} => #{status}"
end

# 3. 保存テスト
filepath = BrightData::ResultStore.save_batch(batch)
puts "\nSaved to: #{filepath}"

# 4. 読込テスト
loaded = BrightData::ResultStore.load_latest
puts "Loaded back: #{loaded.size} results"

puts "\n=== レスポンス構造メモ ==="
puts "★ このメモをDay2の実装に使うこと ★"
sample = batch.first["result"]
puts "organic結果のキー名: #{ (sample["organic_results"] || sample["organic"] || [{}]).first&.keys }"
puts "local_resultsの有無: #{sample.key?("local_results")}"
puts "knowledge_graphの有無: #{sample.key?("knowledge_graph")}"
