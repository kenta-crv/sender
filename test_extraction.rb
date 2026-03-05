# test_extraction.rb
# 実行: bundle exec rails runner test_extraction.rb

batch = BrightData::ResultStore.load_latest
abort "ERROR: SERP結果なし。Day1を先に実行せよ。" if batch.empty?

companies = BrightData::CompanyExtractor.extract_batch(batch)
BrightData::ResultExporter.print_table(companies)
BrightData::ResultExporter.to_csv(companies)

# 問い合わせURL検出テスト（3件のみ）
sample = companies.first(3)
BrightData::ContactUrlEnricher.enrich(sample, headless: true)
BrightData::ResultExporter.print_table(sample)
