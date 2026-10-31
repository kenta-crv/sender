# 発信前の点検（app/services/dial_preflight.rb）が、壊れ方ごとに正しく NG を出すかを確かめる。
# 実行: ruby verification/preflight_eval/run_preflight_eval.rb   （Rails・ネット接続なし）
$LOAD_PATH.unshift File.join(__dir__, 'stub')
require 'tmpdir'
class Object; def blank?; respond_to?(:empty?) ? !!empty? : !self; end; def present?; !blank?; end; def presence; present? ? self : nil; end; end
class NilClass; def blank?; true; end; end
class String; def blank?; strip.empty?; end; end
S = Struct.new(:id, :name)
class DialScript; def self.find_by(id:); $script; end; end
module DialPlaybackCache
  def self.preload!(_); raise 'say が15秒で終わりません' if $rec == :preload_fail; true; end
  def self.fetch(_id, key); return nil if $rec == :missing && key == 'silence_1'; 'x' * 4000; end
end
class TwilioConfig; def self.current; Struct.new(:from_number).new($from); end; end
module Twilio; module REST
  class RestError < StandardError; end
  class Client
    Acc = Struct.new(:status); Bal = Struct.new(:balance, :currency)
    def initialize(*); end
    def api; self; end
    def v2010; self; end
    def accounts(_); self; end
    def fetch
      raise RestError, '[HTTP 401] 20003 : Unable to fetch record' if $tw == :auth
      @bal ? Bal.new($bal, 'USD') : Acc.new($tw == :suspended ? 'suspended' : 'active')
    end
    def balance; @bal = true; self; end
  end
end; end
module DialLlmClient
  def self.ping!
    raise 'HTTP 404: {"error":{"message":"The model `gpt-4.1-nan` does not exist"}}' if $llm == :notfound
    'gpt-4.1-mini-2025-04-14'
  end
end
module TwilioPublicUrl
  def self.ensure_ready!; raise '公開用の接続が切れているため発信できません。ngrok を起動してください。' if $ngrok == :down; 'https://example.ngrok-free.dev'; end
end
require_relative '../../app/services/dial_preflight'

KEYFILE = File.join(Dir.tmpdir, 'preflight_key.json'); File.write(KEYFILE, '{}')
def reset!
  $script = S.new(1, 'テスト原稿'); $rec = :ok; $tw = :ok; $bal = 10.0; $from = '+815000000000'
  $llm = :ok; $ngrok = :ok; Google::Cloud::Speech::V1::Speech::Client.behavior = :ok
  ENV['TWILIO_ACCOUNT_SID'] = 'AC1'; ENV['TWILIO_AUTH_TOKEN'] = 't'; ENV['GOOGLE_APPLICATION_CREDENTIALS'] = KEYFILE
end

CASES = [
  ['すべて正常', -> {}, []],
  ['Twilio アカウント停止（今回の1件目）', -> { $tw = :suspended }, ['Twilio（電話回線）']],
  ['Twilio 認証エラー', -> { $tw = :auth }, ['Twilio（電話回線）']],
  ['Twilio 残高ゼロ', -> { $bal = 0.0 }, ['Twilio（電話回線）']],
  ['Google の鍵が無効（今回の2件目）', -> { Google::Cloud::Speech::V1::Speech::Client.behavior = :invalid_grant }, ['Google 音声認識（相手の声を文字にする）']],
  ['Google が文字を返さない', -> { Google::Cloud::Speech::V1::Speech::Client.behavior = :empty }, ['Google 音声認識（相手の声を文字にする）']],
  ['Google の鍵ファイルがない', -> { ENV['GOOGLE_APPLICATION_CREDENTIALS'] = '/nope/key.json' }, ['Google 音声認識（相手の声を文字にする）']],
  ['鍵ファイルの指定なし（Google アカウントのログインを使う）', -> { ENV['GOOGLE_APPLICATION_CREDENTIALS'] = '' }, []],
  ['ログイン未設定で Google が認証エラー', -> { ENV['GOOGLE_APPLICATION_CREDENTIALS'] = ''; Google::Cloud::Speech::V1::Speech::Client.behavior = :invalid_grant }, ['Google 音声認識（相手の声を文字にする）']],
  ['AI のモデル名違い', -> { $llm = :notfound }, ['AI 判定（OpenAI）']],
  ['録音が足りない', -> { $rec = :missing }, ['録音（音声ファイル）']],
  ['音声変換が止まる', -> { $rec = :preload_fail }, ['録音（音声ファイル）']],
  ['ngrok 停止', -> { $ngrok = :down }, ['公開URL（Twilio からこのMacへの入口）']],
  ['原稿がない', -> { $script = nil }, ['原稿', '録音（音声ファイル）', 'Google 音声認識（相手の声を文字にする）']]
]

pass = 0
CASES.each do |name, setup, expected_ng|
  reset!; setup.call
  checks = DialPreflight.run(public_ping: false)
  ng = checks.reject(&:ok).map(&:name)
  msg = DialPreflight.failure_message(checks)
  ok = ng == expected_ng && (expected_ng.empty? ? msg.nil? : msg.to_s.include?('電話はかけていません'))
  pass += 1 if ok
  puts "#{ok ? 'OK' : 'NG'}  #{name}  → NG項目: #{ng.empty? ? 'なし（発信する）' : ng.join('、') + '（発信しない）'}"
  puts "      期待: #{expected_ng.inspect}" unless ok
end
# 使い回し: OK の結果は使い回し、NG になったら使い回さない
reset!; DialPreflight.run(public_ping: false, cache: true)
$tw = :suspended
cached_ok = DialPreflight.run(public_ping: false, cache: true).all?(&:ok)
DialPreflight.instance_variable_set(:@ok_at, nil)
fresh_ng = !DialPreflight.run(public_ping: false, cache: true).all?(&:ok)
again_ng = !DialPreflight.run(public_ping: false, cache: true).all?(&:ok)
ok = cached_ok && fresh_ng && again_ng
pass += 1 if ok
CASES << ['使い回し']
puts "#{ok ? 'OK' : 'NG'}  OK の結果だけを10分使い回し、NG は毎回確かめ直す"

reset!; $tw = :suspended; Google::Cloud::Speech::V1::Speech::Client.behavior = :invalid_grant
puts "\n--- 表示例（今回の状態を再現） ---\n#{DialPreflight.report(public_ping: false)}"
puts "\n#{pass}/#{CASES.size} 件 OK"
exit(pass == CASES.size ? 0 : 1)
