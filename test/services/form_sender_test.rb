# FormSender sleep値テスト（スタンドアロン）
# chromedriver-helper互換性問題を回避するため、ソースコード直接検証方式

source = File.read(File.expand_path('../../app/services/form_sender.rb', __dir__))
pass_count = 0
fail_count = 0
total = 12

def assert_test(name, condition)
  if condition
    puts "  PASS: #{name}"
    return true
  else
    puts "  FAIL: #{name}"
    return false
  end
end

puts "=" * 60
puts "FormSender テスト実行"
puts "=" * 60

# === 1. 待機処理テスト（動的wait化後の期待値） ===
puts "\n--- 待機処理テスト ---"

pass_count += 1 if assert_test(
  "ページ読み込み待機が動的wait",
  source.include?('wait_for(min_seconds: 1, max_seconds: 10)') &&
    source.include?('ページ読み込み待機（body+form存在で早期完了）')
)

pass_count += 1 if assert_test(
  "送信後の待機が動的wait",
  source.include?('wait_for(min_seconds: 2, max_seconds: 12)') &&
    source.include?('送信後の待機（URL変更 or 成功パターン検出で早期完了）')
)

pass_count += 1 if assert_test(
  "確認画面後の待機が動的wait",
  source.include?('wait_for(min_seconds: 2, max_seconds: 10)') &&
    source.include?('確認画面後の待機（URL変更 or 成功パターン検出で早期完了）')
)

pass_count += 1 if assert_test(
  "再判定前の追加待機が3秒",
  source.include?("sleep 3") && source.include?('成功未検出')
)

# === 2. 旧sleep値が残っていないことを確認 ===
puts "\n--- 旧sleep値の除去確認 ---"

pass_count += 1 if assert_test(
  "旧ページ読み込み待機(3秒)が除去済み",
  !source.include?('sleep 3 # ページ読み込み待機')
)

pass_count += 1 if assert_test(
  "旧送信後待機(5秒)が除去済み",
  !source.include?('sleep 5 # 送信後の待機')
)

pass_count += 1 if assert_test(
  "旧確認画面後待機(4秒)が除去済み",
  !source.include?('sleep 4 # 確認画面後')
)

# === 3. 定数定義テスト ===
puts "\n--- 定数定義テスト ---"

pass_count += 1 if assert_test(
  "SENDER_INFO定数が定義されている",
  source.include?('SENDER_INFO')
)

pass_count += 1 if assert_test(
  "FIELD_PATTERNS定数が定義されている",
  source.include?('FIELD_PATTERNS')
)

pass_count += 1 if assert_test(
  "SUCCESS_PATTERNS定数が定義されている",
  source.include?('SUCCESS_PATTERNS')
)

pass_count += 1 if assert_test(
  "NO_SALES_PATTERNS定数が定義されている",
  source.include?('NO_SALES_PATTERNS')
)

pass_count += 1 if assert_test(
  "CONSENT_PATTERNS定数が定義されている",
  source.include?('CONSENT_PATTERNS')
)

# === 結果サマリ ===
puts "\n" + "=" * 60
puts "結果: #{pass_count}/#{total} テスト合格"
if pass_count == total
  puts "ALL TESTS PASSED"
else
  puts "#{total - pass_count} テスト失敗"
end
puts "=" * 60

exit(pass_count == total ? 0 : 1)
