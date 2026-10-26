# 受付の返答例を、今の判定（LLMなし＝文字列ルール）に通して一覧を出す。
# 実行: ruby verification/front_eval/run_eval.rb  （Rails不要）
require 'csv'
class Object; def blank?; respond_to?(:empty?) ? !!empty? : !self; end; def present?; !blank?; end; def presence; present? ? self : nil; end; end
class NilClass; def blank?; true; end; end
class String; def blank?; strip.empty?; end; end
module Rails; def self.logger; @l ||= Class.new { def method_missing(*) end }.new; end; end
class Call; end
module TwilioService; def self.utf8_speech(t); t.to_s.strip; end; end
module DialLlmClient; def self.enabled?; false; end; end
module DialPlaybackCache
  Entry = Struct.new(:branch_id, :recording_id, :transfer, :text, keyword_init: true)
  KEYS = %w[wait smalltalk faq transfer 着信不在 フロントアウト 担当者不在 電話不通 clarify clarify_alt clarify_simple callback purpose]
  def self.allowlist(_); KEYS.map { |k| Entry.new(branch_id: k, recording_id: k, transfer: k == 'transfer') }; end
end
root = File.expand_path('../..', __dir__)
load File.join(root, 'app/services/dial_realtime_decider.rb')

dir = __dir__
rows = CSV.read(File.join(dir, 'cases.tsv'), col_sep: "\t", headers: true)
out = []
rows.each do |r|
  d = DialRealtimeDecider.decide(r['text'], call: nil, llm: :auto)
  exp = r['expected']
  result = if exp.start_with?('NEW:') then '分岐なし'
           elsif d.branch_id == exp then 'OK'
           else 'NG' end
  out << [result, exp, d.branch_id, r['text'], r['note']]
end
CSV.open(File.join(dir, 'results.csv'), 'w') do |c|
  c << %w[判定 正解 今の判定 発話 メモ]
  out.each { |o| c << o }
end
scored = out.reject { |o| o[0] == '分岐なし' }
ok = scored.count { |o| o[0] == 'OK' }
puts "既存分岐 #{scored.size}件中 正解 #{ok}件 (#{(ok * 100.0 / scored.size).round(1)}%)  分岐なし #{out.size - scored.size}件"
scored.group_by { |o| o[1] }.each { |k, v| puts "  #{k}: #{v.count { |o| o[0] == 'OK' }}/#{v.size}" }
puts '--- NG'
out.select { |o| o[0] == 'NG' }.each { |o| puts o[1..4].join(' | ') }
puts '--- 分岐なし'
out.select { |o| o[0] == '分岐なし' }.each { |o| puts o[1..3].join(' | ') }
