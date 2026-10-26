# 通話セッション（lib/bidirectional_call_session.rb）の動きを、Twilio・Rails なしで確かめる。
# 実行: ruby verification/session_eval/run_session_eval.rb
# 待ち時間は短く縮めて回す（本番の値は BidirectionalCallSession::TIMING）。
require 'json'
require 'base64'

class Object; def blank?; respond_to?(:empty?) ? !!empty? : !self; end; def present?; !blank?; end; def presence; present? ? self : nil; end; end
class NilClass; def blank?; true; end; end
class String; def blank?; strip.empty?; end; end
module Rails
  def self.logger; @l ||= Class.new { def error(m); warn(m); end; def method_missing(*) end }.new; end
  def self.application; @a ||= Struct.new(:executor).new(Class.new { def wrap; yield; end }.new); end
end
class Call; end
module CallLatencyLog
  @events = Queue.new
  def self.record(_id, event, turn_id: nil, at_mono: nil, extra: {}); @events << [event, extra]; end
  def self.drain; out = []; out << @events.pop until @events.empty?; out; end
end
module CallTranscriptBroadcaster; def self.broadcast(*, **); end; end
module DialTransferService
  THANKS_TEXT = 'お忙しい中ご対応ありがとうございます。'
  def self.start_operator!(*); end
  def self.cancel_operator!(*); end
end
module DialRealtimeDecider
  Decision = Struct.new(:branch_id, :recording_id, :transfer, :path, :ambiguous, keyword_init: true)
end
module TwilioService
  def self.utf8_speech(t); t.to_s.strip; end
  def self.hangup_script?(k); %w[callback 着信不在 フロントアウト 担当者不在 電話不通].include?(k.to_s); end
  def self.script_text(k, _c = nil); k.to_s; end
end
$redirects = Queue.new
class CallRedirector
  def redirect_handoff(_sid, _id, script, hangup:); $redirects << [script, hangup]; end
end

KEYS = %w[greeting wait smalltalk clarify clarify_simple silence_1 silence_2 callback transfer 着信不在 フロントアウト 担当者不在 電話不通]
module DialPlaybackCache
  def self.fetch(_sid, key); i = KEYS.index(key.to_s); i ? ([i + 1].pack('C') * 1600) : nil; end
end

root = File.expand_path('../..', __dir__)
require File.join(root, 'lib/mulaw')
require File.join(root, 'lib/bidirectional_call_session')

class FakeWs
  attr_reader :plays
  def initialize; @plays = []; @last = nil; end
  def send(data)
    msg = JSON.parse(data)
    if msg['event'] == 'media'
      key = KEYS[Base64.decode64(msg['media']['payload']).bytes.first - 1]
      @plays << key if key != @last
      @last = key
    elsif msg['event'] == 'clear'
      @last = nil
    end
  end
end

TABLE = {
  'はい、山田商事です' => ['smalltalk', false],
  'ただいま電話に出ることができません' => ['着信不在', false],
  '少々お待ちください' => ['wait', false],
  'もう少々お待ちください' => ['wait', false],
  '♪♪♪' => ['clarify', true],
  'お電話代わりました、田中です' => ['transfer', false],
  'ただいま席を外しております' => ['担当者不在', false],
  'むにゃむにゃ' => ['clarify', true],
  'ご用件は' => ['purpose', false]
}
class TableDecider
  def self.decide(text, **)
    sleep 4 if text == 'SLOW'
    b, amb = TABLE.fetch(text, ['wait', false])
    DialRealtimeDecider::Decision.new(branch_id: b, recording_id: b, transfer: b == 'transfer', path: 'test', ambiguous: amb)
  end
end

TIMING = { greet_wait: 0.3, silence_step: 0.5, hold_max: 6.0, watchdog: 1.5, tick: 0.1 }

class Run
  attr_reader :ws, :s, :hangups
  def initialize
    @ws = FakeWs.new
    @hangups = []
    CallLatencyLog.drain
    $redirects.pop until $redirects.empty?
    @s = BidirectionalCallSession.new(@ws, call_id: 1, call_sid: 'CA', stream_sid: 'MZ', persist: false,
                                      decider: TableDecider, timing: TIMING, hangup: ->(sid) { @hangups << sid },
                                      vad: UtteranceVad.new(max_utterance_ms: 1000))
    @s.start!
  end
  def frame(tone) = tone ? Mulaw.tone(160, amplitude: 12000) : Mulaw.silence(160)
  def feed_for(sec, tone)
    (sec / 0.02).round.times { @s.feed(frame(tone)); sleep 0.02 }
  end
  def quiet(sec) = feed_for(sec, false)
  def speak(text, sec = 0.6)
    feed_for(sec, true)
    @s.on_final(text, 0.9) if text # 認識結果は話し終わりの直後に届く
    quiet(0.6)
  end
  def wait_play
    50.times { break unless @s.instance_variable_get(:@playing) || @s.instance_variable_get(:@busy); quiet(0.1) }
  end
  def events = (@events ||= []).concat(CallLatencyLog.drain)
  def redirects; out = []; out << $redirects.pop until $redirects.empty?; (@red ||= []).concat(out); end
  def done; @s.finish; sleep 0.2; end
end

$results = []
def scenario(name, expect)
  r = Run.new
  yield r
  plays = r.ws.plays
  red = r.redirects
  ev = r.events.map(&:first)
  r.done
  checks = expect.call(plays, red, ev, r)
  ok = checks.all? { |_, v| v }
  $results << ok
  puts "#{ok ? 'OK ' : 'NG '} #{name}"
  puts "     再生: #{plays.join(' → ')}"
  puts "     切断/転送: #{red.map { |sc, h| h ? "録音後に切断(#{sc})" : "転送(#{sc})" }.join(', ')}#{r.hangups.any? ? ' 無言で切断' : ''}"
  checks.each { |k, v| puts "     #{v ? '✓' : '✗'} #{k}" unless v }
end

scenario('1. 第一声のあと挨拶 → 無言が続くと もしもし → 電話が遠い → 改めて で切る',
  ->(p, red, _ev, _r) { { '再生順' => p == %w[greeting silence_1 silence_2 callback], '最後に切断' => red == [['callback', true]] } }) do |r|
  r.quiet(0.2); r.speak('はい、山田商事です'); r.wait_play; r.quiet(2.5)
end

scenario('2. 相手が名乗らなければ 0.3秒（本番1.5秒）で挨拶する',
  ->(p, _red, _ev, _r) { { '挨拶した' => p.first == 'greeting' } }) do |r|
  r.quiet(0.6)
end

scenario('3. 第一声が留守電なら、挨拶を止めて何も残さず切る',
  ->(p, red, ev, r) { { '無言で切断' => r.hangups.size == 1, '留守電判定' => ev.include?('opening_machine'), '他の録音なし' => (p - ['greeting']).empty?, 'リダイレクトなし' => red.empty? } }) do |r|
  r.speak('ただいま電話に出ることができません'); r.quiet(1.0)
end

scenario('4. 保留中は保留音を無視し、何も言わない。「もう少々」で延長し、6秒（本番60秒）で無言切断',
  ->(p, red, ev, r) { { '再生は挨拶と待ちだけ' => p == %w[greeting wait], '保留音を無視' => ev.count('turn_ignored') >= 2, '延長あり' => r.events.any? { |e, x| e == 'turn_ignored' && x[:reason] == 'hold_wait' }, '無言で切断' => r.hangups.size == 1 && red.empty? } }) do |r|
  r.quiet(0.4); r.wait_play
  r.speak('少々お待ちください'); r.wait_play
  r.speak('♪♪♪', 1.2); r.speak(nil, 1.2)          # 保留音（文字あり・文字なし）
  r.speak('もう少々お待ちください'); r.quiet(6.6)
end

scenario('5. 保留明け「代わりました」で転送',
  ->(p, red, _ev, _r) { { '再生順' => p == %w[greeting wait transfer], '転送' => red == [['transfer', false]] } }) do |r|
  r.quiet(0.4); r.wait_play
  r.speak('少々お待ちください'); r.wait_play; r.quiet(0.8)
  r.speak('お電話代わりました、田中です'); r.wait_play
end

scenario('6. 保留明け「不在」で、不在の録音を流して切る',
  ->(p, red, _ev, _r) { { '再生順' => p == %w[greeting wait 担当者不在], '切断' => red == [['担当者不在', true]] } }) do |r|
  r.quiet(0.4); r.wait_play
  r.speak('少々お待ちください'); r.wait_play; r.quiet(0.8)
  r.speak('ただいま席を外しております'); r.wait_play
end

scenario('7. 会話中に雑音が続いても固まらない（1秒で強制区切り → 無言扱い）',
  ->(p, _red, ev, _r) { { '強制区切り' => ev.include?('forced_cut'), 'もしもしへ進んだ' => p.include?('silence_1') } }) do |r|
  r.quiet(0.4); r.wait_play
  r.speak(nil, 1.3); r.wait_play
end

scenario('8. 聞き取れない返事が3回続くと 聞き返し → はい/いいえ → 改めて で切る',
  ->(p, red, _ev, _r) { { '再生順' => p == %w[greeting clarify clarify_simple callback], '切断' => red == [['callback', true]] } }) do |r|
  r.quiet(0.4); r.wait_play
  3.times { r.speak('むにゃむにゃ'); r.wait_play }
end

scenario('9. 録音が無い分岐は、黙らずに聞き返しを流す',
  ->(p, _red, ev, _r) { { '録音なしを記録' => ev.include?('audio_cache_miss'), '聞き返し' => p == %w[greeting clarify] } }) do |r|
  r.quiet(0.4); r.wait_play
  r.speak('ご用件は'); r.wait_play
end

scenario('10. 判定が止まっても、見張りが1.5秒（本番10秒）で次へ進める',
  ->(p, _red, ev, _r) { { '見張り発動' => ev.include?('watchdog'), 'もしもしへ進んだ' => p.include?('silence_1'), '遅れた判定は捨てた' => !p.include?('wait') } }) do |r|
  r.quiet(0.4); r.wait_play
  r.speak('SLOW'); r.quiet(4.5)
end

puts "\n#{$results.count(true)}/#{$results.size} 件 OK"
exit($results.all? ? 0 : 1)
