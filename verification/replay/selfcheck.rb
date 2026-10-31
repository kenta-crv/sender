# 再現テストの「仕組み」だけを Rails・ネット接続なしで確かめる（音声認識と AI は偽物）。
# 本物の確認は run_replay.rb。これは run_replay.rb 自体の不具合を先に見つけるためのもの。
# 実行: ruby verification/replay/selfcheck.rb
ROOT = File.expand_path('../..', __dir__)
class Object; def blank?; respond_to?(:empty?) ? !!empty? : !self; end; def present?; !blank?; end; def presence; present? ? self : nil; end; end
class NilClass; def blank?; true; end; end
class String; def blank?; strip.empty?; end; end
module Rails
  def self.logger; @l ||= Class.new { def error(m) = warn("ERR #{m}"); def method_missing(*) end }.new; end
  def self.application; @a ||= Struct.new(:executor).new(Class.new { def wrap; yield; end }.new); end
end
require File.join(ROOT, 'lib/mulaw')

# 偽の音声認識。10/29 の本物の結果に合わせて遅らせる:
#   通話の最初の発話 … 途中結果なし、確定結果は話し終わりの 2.5 秒後
#   それ以降       … 0.2 秒後に文の前半だけの途中結果、1.2 秒後に確定結果
$speaking = nil
class GoogleSpeechStream
  def initialize(on_result:, on_interim: nil, **); @on_result = on_result; @on_interim = on_interim; @voiced = 0; @quiet = 0; @n = 0; end
  def start; end
  def stop; end
  def feed_audio(bytes)
    if Mulaw.rms(bytes) > 1500 then @voiced += 1; @quiet = 0
    elsif @voiced > 5
      @quiet += 1
      text = $speaking.to_s
      first = @n.zero?
      @on_interim&.call(text[0, (text.size / 2.0).ceil], 0.0) if !first && @quiet == 10
      if @quiet == (first ? 125 : 60)
        @voiced = 0
        @n += 1
        Thread.new { @on_result.call(text, 0.9) } unless text.empty?
      end
    end
  end
end
$LOADED_FEATURES << File.join(ROOT, 'lib/google_speech_stream.rb')
$LOADED_FEATURES << File.join(ROOT, 'lib/call_redirector.rb')

class FakeCall
  attr_accessor :id, :dial_script_id, :unknown_streak, :ctx
  def initialize(id); @id = id; @dial_script_id = 1; @unknown_streak = 0; @ctx = {}; end
  def persisted? = true
  def update(*) = true
  # 10/30 の本物の実行では DB の書き込みが数秒待たされ、音声の送受信まで止まった。
  # それを再現するため、DB への書き込みはわざと 2 秒かかるようにする
  def append_call_turn!(*) = sleep(2)
  def save_selected_status!(*) = sleep(2)
  def conversation_context_hash = @ctx
  def remember_context!(them:, script:, us:); @ctx = { 'last_script' => script, 'topic' => script }; end
end
$call = FakeCall.new(1)
class Call; def self.find_by(**) = $call; end
class TwilioConfig; def self.current = Struct.new(:speech_hints).new(''); end
module CallTranscriptBroadcaster; def self.broadcast(*, **); end; end
module DialFlowEngine; def self.note_unclear!(*, **); end; def self.note_clear!(*); end; end
LOG = []
module CallLatencyLog; def self.record(_id, ev, turn_id: nil, at_mono: nil, extra: {}); LOG << [ev, extra]; end; end
ACTIONS = []
module DialTransferService
  THANKS_TEXT = 'x'
  def self.start_operator!(*) = ACTIONS << [:operator_dial, nil, 0]
  def self.cancel_operator!(*); end
end
class CallRedirector
  def redirect_handoff(_s, _i, script, hangup:) = ACTIONS << [hangup ? :hangup : :transfer, script, 0]
end
module TwilioService
  def self.utf8_speech(t) = t.to_s.strip
  def self.hangup_script?(k) = %w[callback 着信不在 フロントアウト 担当者不在 電話不通].include?(k.to_s)
  def self.script_text(k, _c = nil) = k.to_s
  def self.bidirectional_call?(_c) = true
  def self.new = Class.new { def hangup_call(_) = ACTIONS << [:silent_hangup, nil, 0] }.new
end
KEYS = %w[greeting wait smalltalk purpose clarify clarify_simple silence_1 silence_2 callback transfer 着信不在 フロントアウト 担当者不在]
# 録音はキーごとに長さの違う音（本物と同じく、先頭は無音）
REC = KEYS.each_with_index.to_h { |k, i| [k, Mulaw.silence(800) + Mulaw.tone((k == 'greeting' ? 24000 : 4000) + i * 800, amplitude: 9000 + i * 100)] }
module DialPlaybackCache; def self.fetch(_s, k) = REC[k.to_s]; end
module DialRealtimeDecider
  Decision = Struct.new(:branch_id, :recording_id, :transfer, :path, :ambiguous, keyword_init: true)
  # 偽の AI: 文の中身でおおまかに分ける
  def self.decide(text, call: nil, **)
    b = case text
        when /電話に出ることができません/ then '着信不在'
        when /代わりました|お待たせいたしました、担当/ then (call&.ctx&.dig('last_script') == 'wait' || true) ? 'transfer' : 'clarify'
        when /私です/ then 'transfer'
        when /席を外/ then '担当者不在'
        when /お断り/ then 'フロントアウト'
        when /ご用件/ then 'purpose'
        when /お待ち/ then 'wait'
        when /もしもし|でございます|山田商事です/ then 'smalltalk'
        else 'clarify'
        end
    Decision.new(branch_id: b, recording_id: b, transfer: b == 'transfer', path: 'fake', ambiguous: b == 'clarify')
  end
end
require File.join(ROOT, 'lib/media_stream_handler')
require_relative 'replay_driver'
require_relative 'scenarios'

def speech(text) = Mulaw.tone((text.size * 0.09 * 8000).round, amplitude: 12000)
def music(sec) = Mulaw.tone((sec * 8000).round, amplitude: 4000)

passed = 0
only = ENV['ONLY'].to_s.split(',').map(&:to_i)
SCENARIOS.each_with_index do |sc, idx|
  next if only.any? && !only.include?(idx + 1)
  ACTIONS.clear; LOG.clear; $call = FakeCall.new(idx + 1)
  d = ReplayDriver.new(recordings: REC, noise_frame: -> { Mulaw.silence(160) }, actions: ACTIONS)
  d.start(MediaStreamHandler.new(d.ws), call_id: idx + 1, call_sid: 'CA', stream_sid: 'MZ')
  sc[:steps].each do |kind, arg|
    break if d.ended?
    case kind
    when :say then $speaking = arg; d.say(arg, speech(arg))
    when :wait_ours then d.wait_ours(gap: arg)
    when :music then $speaking = '♪'; d.play_music(arg, music(arg))
    when :silence then d.silence(arg)
    end
  end
  d.wait_end(sc[:end_wait] || (sc[:end] ? 15 : 2)); sleep 0.5; d.stop
  played = d.plays.map(&:key) - ['partial']; all = d.plays.map(&:key)
  end_action = ACTIONS.map(&:first).find { |k| %i[hangup transfer silent_hangup].include?(k) }
  plays_ok = sc[:plays_prefix] ? (all.empty? || all == ['partial'] || all.first(sc[:plays].size) == sc[:plays]) : ([sc[:plays]] + Array(sc[:plays_alt])).include?(played)
  ok = plays_ok && end_action == sc[:end] && d.failures.empty?
  passed += 1 if ok
  puts "#{ok ? 'OK' : 'NG'}  #{idx + 1}. #{sc[:name]}"
  puts "    実際: #{all.join(' → ')} → #{end_action || '（通話継続）'}  #{d.failures.join(' / ')}" unless ok
  LOG.each { |e, x| puts "      #{e} #{x}" } if !ok && ENV['DEBUG']
end
total = only.any? ? only.size : SCENARIOS.size
puts "\n#{passed}/#{total} 件 OK"
exit(passed == total ? 0 : 1)
