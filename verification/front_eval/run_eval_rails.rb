# 受付の返答例を、AI判定ありの DialRealtimeDecider に通して一覧を出す。
# 実行: bin/rails runner verification/front_eval/run_eval_rails.rb
# 既定モデルは変えず、このプロセスの中だけで DIAL_LLM_MODEL を切り替える。
require 'csv'

CUTTING_BRANCHES = %w[着信不在 フロントアウト 担当者不在 電話不通 callback].freeze
SAFE_EXPECTED = %w[wait transfer].freeze
COMPARE_MODELS = %w[gpt-4.1-nano gpt-4.1-mini].freeze
EXPECTED_CATEGORY = {
  'transfer' => '本人',
  'wait' => '取り次ぎ',
  '担当者不在' => '不在',
  'フロントアウト' => '断り',
  'callback' => '改めて',
  'purpose' => '用件確認',
  'smalltalk' => '挨拶',
  '着信不在' => '留守電',
  'clarify' => '不明'
}.freeze
WAIT_CONTEXT = {
  'turns' => [
    { 'them' => '担当の者を呼んでまいります', 'script' => 'wait', 'us' => '承知しました' }
  ],
  'last_them' => '担当の者を呼んでまいります',
  'last_script' => 'wait',
  'last_us' => '承知しました',
  'topic' => 'wait'
}.freeze

module FrontEvalChatJsonProbe
  def chat_json(*args, **kwargs)
    result = super
    Thread.current[:front_eval_chat_json] = result
    Thread.current[:front_eval_llm_nil] = result.nil?
    result
  rescue
    Thread.current[:front_eval_chat_json] = nil
    Thread.current[:front_eval_llm_nil] = true
    raise
  end
end
DialLlmClient.singleton_class.prepend(FrontEvalChatJsonProbe)

def use_dial_model(name)
  previous = DialLlmClient::CHAT_MODEL
  previous_env = ENV['DIAL_LLM_MODEL']
  ENV['DIAL_LLM_MODEL'] = name
  DialLlmClient.send(:remove_const, :CHAT_MODEL)
  DialLlmClient.const_set(:CHAT_MODEL, name)
  yield
ensure
  ENV['DIAL_LLM_MODEL'] = previous_env
  DialLlmClient.send(:remove_const, :CHAT_MODEL) if DialLlmClient.const_defined?(:CHAT_MODEL, false)
  DialLlmClient.const_set(:CHAT_MODEL, previous)
end

dir = Rails.root.join('verification/front_eval')
script = DialScript.find(1)
raise 'DialPlaybackCache.preload! が原稿 ID 1 を読み込めませんでした' unless DialPlaybackCache.preload!(script)
raise 'DialLlmClient が無効です。APIキーを読めません' unless DialLlmClient.enabled?

allowed_ids = DialPlaybackCache.allowlist(script.id).map(&:branch_id).uniq
call = Call.new(dial_script_id: 1)
rows = CSV.read(dir.join('cases.tsv'), col_sep: "\t", headers: true)
all_out = []
summaries = []

COMPARE_MODELS.each do |model|
  out = []
  use_dial_model(model) do
    rows.each do |r|
      expected = r['expected'].to_s
      call.conversation_context = expected == 'transfer' ? JSON.generate(WAIT_CONTEXT) : nil
      Thread.current[:front_eval_llm_nil] = true
      Thread.current[:front_eval_chat_json] = nil
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      decision = DialRealtimeDecider.decide(r['text'], call: call, llm: :auto)
      elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round
      route = Thread.current[:front_eval_llm_nil] ? 'ルール' : 'AI'
      raw = Thread.current[:front_eval_chat_json]
      category = raw.is_a?(Hash) ? raw['category'].to_s.strip : ''
      mapped = DialRealtimeDecider::CATEGORY_BRANCH[category]
      missing_recording = route == 'AI' && mapped.present? && mapped != 'clarify' &&
                          !allowed_ids.include?(mapped) && decision.branch_id == 'clarify'
      category_match = EXPECTED_CATEGORY[expected] == category
      result = if expected.start_with?('NEW:')
                 '分岐なし'
               elsif decision.branch_id == expected
                 'OK'
               else
                 'NG'
               end
      out << {
        model: model,
        result: result,
        expected: expected,
        branch: decision.branch_id,
        text: r['text'],
        note: r['note'],
        ms: elapsed_ms,
        route: route,
        category: category,
        missing_recording: missing_recording,
        category_match: category_match
      }
    end
  end
  all_out.concat(out)

  scored = out.reject { |row| row[:result] == '分岐なし' }
  ok = scored.count { |row| row[:result] == 'OK' }
  rate = scored.empty? ? 0.0 : (ok * 100.0 / scored.size).round(1)
  ai_failure = out.count { |row| row[:route] == 'ルール' }
  times = out.map { |row| row[:ms] }
  cut_while_waiting = out.select { |row| SAFE_EXPECTED.include?(row[:expected]) && CUTTING_BRANCHES.include?(row[:branch]) }
  wrong_transfer = out.select { |row| row[:expected] != 'transfer' && row[:branch] == 'transfer' }
  missing_rows = out.select { |row| row[:missing_recording] }
  missing_match = missing_rows.count { |row| row[:category_match] }
  summaries << {
    model: model,
    scored: scored.size,
    ok: ok,
    rate: rate,
    none: out.size - scored.size,
    ai_failure: ai_failure,
    avg_ms: times.empty? ? 0 : (times.sum / times.size.to_f).round,
    max_ms: times.max.to_i,
    cut: cut_while_waiting.size,
    wrong_transfer: wrong_transfer.size,
    missing: missing_rows.size,
    missing_match: missing_match
  }

  puts "=== #{model} ==="
  if ai_failure.positive?
    puts "警告: AI失敗が #{ai_failure} 件あります。DialLlmClient.chat_json が nil のため、文字列ルールの結果が混ざっています。"
  end
  puts "既存分岐 #{scored.size}件中 正解 #{ok}件 (#{rate}%)  分岐なし #{out.size - scored.size}件"
  puts "AI成功 #{out.size - ai_failure}件 / AI失敗 #{ai_failure}件"
  puts "平均判定時間 #{summaries.last[:avg_ms]}ミリ秒  最大判定時間 #{summaries.last[:max_ms]}ミリ秒"
  puts "危険な誤判定（待ちか転送なのに切った） #{cut_while_waiting.size}件"
  cut_while_waiting.each { |row| puts [row[:expected], row[:branch], row[:text], row[:note], row[:ms], row[:route]].join(' | ') }
  puts "危険な誤判定（転送以外なのに転送した） #{wrong_transfer.size}件"
  wrong_transfer.each { |row| puts [row[:expected], row[:branch], row[:text], row[:note], row[:ms], row[:route]].join(' | ') }
  puts "録音が原稿に無いため clarify になった #{missing_rows.size}件（AIの分類が合っていた #{missing_match}件）"
  missing_rows.each do |row|
    mark = row[:category_match] ? '分類一致' : '分類不一致'
    puts "  #{row[:expected]} | #{row[:category]} | #{mark} | #{row[:text]}"
  end
end

CSV.open(dir.join('results_llm.csv'), 'w') do |csv|
  csv << %w[モデル 判定 正解 今の判定 発話 メモ 判定時間ms 判定経路 分類 録音なしclarify 分類一致]
  all_out.each do |row|
    csv << [
      row[:model], row[:result], row[:expected], row[:branch], row[:text], row[:note],
      row[:ms], row[:route], row[:category],
      row[:missing_recording] ? 'yes' : '',
      row[:category_match] ? 'yes' : ''
    ]
  end
end

puts '=== 比較 ==='
header = %w[モデル 正解率 待ちか転送なのに切った 転送以外なのに転送した 平均ms 最大ms AI失敗 録音なしclarify うち分類一致]
puts header.join("\t")
summaries.each do |row|
  puts [
    row[:model],
    "#{row[:ok]}/#{row[:scored]} (#{row[:rate]}%)",
    row[:cut],
    row[:wrong_transfer],
    row[:avg_ms],
    row[:max_ms],
    row[:ai_failure],
    row[:missing],
    row[:missing_match]
  ].join("\t")
end
