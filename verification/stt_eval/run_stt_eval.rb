# 音声認識の接続（lib/google_speech_stream.rb）が、切れてもつなぎ直すか・認証エラーでは止まるかを確かめる。
# 実行: ruby verification/stt_eval/run_stt_eval.rb   （Rails・ネット接続なし）
$LOAD_PATH.unshift File.join(__dir__, 'stub')
class Object; def blank?; respond_to?(:empty?) ? !!empty? : !self; end; def present?; !blank?; end; end
class NilClass; def blank?; true; end; end
module Rails; def self.logger; @l ||= Class.new { def method_missing(*) end }.new; end; end
require_relative '../../lib/google_speech_stream'

def voice(ms) = Mulaw.tone(8 * ms, amplitude: 12000)
def run_case(plan, feed_sec: 2.0)
  $stt_plan = plan.dup; $stt_connections = 0; $stt_bytes = 0
  finals = []; errors = []
  s = GoogleSpeechStream.new(call_id: 1, on_result: ->(t, _c) { finals << t }, on_error: ->(e) { errors << e.message })
  s.start
  (feed_sec / 0.02).round.times { |i| s.feed_audio(i % 50 < 25 ? voice(20) : Mulaw.silence(160)); sleep 0.02 }
  s.stop
  { conns: $stt_connections, finals: finals, errors: errors, bytes: $stt_bytes }
end

results = []
check = ->(name, ok, info) { results << ok; puts "#{ok ? 'OK' : 'NG'}  #{name}  #{info}" }

r = run_case([:normal])
check.('正常: 結果が届く', r[:finals] == ['もしもし'] && r[:errors].empty?, r)
r = run_case([:timeout, :normal], feed_sec: 3.0)
check.('一時的な切断（無音の時間切れ）: つなぎ直して、その後の結果も届く', r[:conns] >= 2 && r[:finals].include?('もしもし') && r[:errors].empty?, r)
r = run_case([:end, :normal], feed_sec: 3.0)
check.('接続が自然に終わった（約5分の上限）: つなぎ直す', r[:conns] >= 2 && r[:errors].empty?, r)
r = run_case([:auth])
check.('認証エラー: つなぎ直さずに通話側へ知らせる', r[:conns] == 1 && r[:errors].size == 1, r)
r = run_case([:timeout] * 30, feed_sec: 4.0)
check.('何度つないでも切れる: 上限（10回）で通話側へ知らせる', r[:errors].size == 1 && r[:conns] == 11, r)

# 無音だけが続いても、4秒ごとに短い無音を送って接続を保つ
$stt_plan = [:normal]; $stt_connections = 0; $stt_bytes = 0
s = GoogleSpeechStream.new(call_id: 1, on_result: ->(*) {}, on_error: ->(*) {})
s.start
(9.0 / 0.02).round.times { s.feed_audio(Mulaw.silence(160)); sleep 0.02 }
s.stop
check.('無音だけが9秒続く: 短い無音を2回送って接続を保つ', $stt_bytes == 1600, { bytes: $stt_bytes })

puts "\n#{results.count(true)}/#{results.size} 件 OK"
exit(results.all? ? 0 : 1)
