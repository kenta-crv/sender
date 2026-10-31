# 電話をかけずに、本物の通話処理を最初から最後まで通すテスト。
#   本物: 音声の区切り判定 / Google 音声認識 / AI 判定 / 通話の流れ / 録音の再生
#   偽物: Twilio への操作（切断・転送・担当者への発信）だけ。記録するだけで実際には行わない
#
# 実行:   ruby bin/rails runner verification/replay/run_replay.rb
# 一部だけ: ONLY=1,3 ruby bin/rails runner verification/replay/run_replay.rb
# 結果は画面と verification/replay/last_result.txt に出る。
require 'digest'
require 'fileutils'
require 'tmpdir'
require_relative 'replay_driver'
require Rails.root.join('lib/media_stream_handler').to_s

ACTIONS = []

# ---- Twilio への操作は記録だけにする ----
DialTransferService.singleton_class.prepend(Module.new do
  def start_operator!(call)
    ACTIONS << [:operator_dial, call&.id, Process.clock_gettime(Process::CLOCK_MONOTONIC)]
  end

  def cancel_operator!(_call); end
end)
CallRedirector.prepend(Module.new do
  def initialize; end

  def redirect_handoff(_sid, _id, script, hangup:)
    ACTIONS << [hangup ? :hangup : :transfer, script, Process.clock_gettime(Process::CLOCK_MONOTONIC)]
  end

  def redirect_script(_sid, _id, script, hangup:)
    ACTIONS << [hangup ? :hangup : :redirect, script, Process.clock_gettime(Process::CLOCK_MONOTONIC)]
  end

  def redirect_transfer(_sid, _id)
    ACTIONS << [:transfer, 'transfer', Process.clock_gettime(Process::CLOCK_MONOTONIC)]
  end
end)
TwilioService.prepend(Module.new do
  def hangup_call(_sid)
    ACTIONS << [:silent_hangup, nil, Process.clock_gettime(Process::CLOCK_MONOTONIC)]
  end
end)

# ---- 受付役の声（こちらとは別の声で読み上げる）----
module ReceptionistVoice
  DIR = Rails.root.join('tmp/replay_audio')

  def self.voice
    @voice ||= begin
      list = `say -v '?' 2>/dev/null`
      %w[Otoya Hattori O-ren Kyoko].find { |v| list.match?(/^#{Regexp.escape(v)}\s/) }
    end
  end

  def self.audio(text)
    FileUtils.mkdir_p(DIR)
    path = DIR.join("#{Digest::SHA256.hexdigest("#{voice}|#{text}")[0, 16]}.ulaw")
    return File.binread(path) if File.exist?(path)

    Dir.mktmpdir do |dir|
      aiff = File.join(dir, 'in.aiff')
      wav = File.join(dir, 'in.wav')
      args = ['say', '-o', aiff]
      args += ['-v', voice] if voice
      args << text
      raise "読み上げに失敗: #{text}" unless system(*args) && File.exist?(aiff)
      raise "変換に失敗: #{text}" unless system('afconvert', '-f', 'WAVE', '-d', 'LEI16@8000', '-c', '1', aiff, wav)

      pcm = DialPlaybackCache.send(:pcm16_from_wav, wav)
      File.binwrite(path, Mulaw.pcm16_to_mulaw(pcm))
    end
    File.binread(path)
  end

  # 回線の小さな雑音（声とはみなされない大きさ）
  NOISE = Array.new(50) { Array.new(160) { rand(-120..120) }.map { |v| Mulaw.encode(v) }.pack('C*') }
  def self.noise_frame
    NOISE.sample
  end

  # 保留音（メロディ）
  def self.music(seconds)
    notes = [523, 587, 659, 698, 784, 698, 659, 587]
    out = String.new(encoding: 'BINARY')
    i = 0
    total = (seconds * 8000).round
    while out.bytesize < total
      freq = notes[(i / 4000) % notes.size]
      out << Mulaw.encode((Math.sin(2 * Math::PI * freq * i / 8000.0) * 3000).round).chr
      i += 1
    end
    out
  end
end

require_relative 'scenarios'

# ---- 実行 ----
lines = []
out = ->(s = '') { puts s; lines << s }

only = ENV['ONLY'].to_s.split(',').map(&:to_i)
script = DialScript.find(1)

out.call('===== 実通話の再現テスト =====')
checks = DialPreflight.run(public_ping: false, script: script)
bad = checks.reject(&:ok).reject { |c| c.name.start_with?('公開URL') || c.name.start_with?('Twilio') }
if bad.any?
  out.call('発信前の点検で、このテストに必要なものが NG のため中止します:')
  bad.each { |c| out.call("  NG #{c.name}: #{c.detail}") }
  File.write(Rails.root.join('verification/replay/last_result.txt'), lines.join("\n"))
  exit 1
end
out.call("受付役の声: #{ReceptionistVoice.voice || '既定'}（こちらの声とは別）")

DialPlaybackCache.preload!(script)
recordings = DialPlaybackCache.allowlist(script.id).to_h { |e| [e.recording_id, DialPlaybackCache.fetch(script.id, e.recording_id)] }
# 受付役の声は先に全部作っておく（作る時間で相手の第一声が遅れないように）
SCENARIOS.each { |sc| sc[:steps].each { |kind, arg| ReceptionistVoice.audio(arg) if kind == :say } }
customer = Customer.find_by(company: '試験発信') || Customer.create!(company: '試験発信', tel: TwilioConfig::TEST_TO_DISPLAY)

passed = 0
SCENARIOS.each_with_index do |sc, idx|
  num = idx + 1
  next if only.any? && !only.include?(num)

  ACTIONS.clear
  call = Call.create!(customer: customer, call_type: 'auto_phone', dial_script_id: script.id,
                      twilio_status: 'replay_test', flow_phase: 'talking', started_at: Time.current)
  CallLatencyLog.clear!(call.id)
  driver = ReplayDriver.new(recordings: recordings, noise_frame: -> { ReceptionistVoice.noise_frame }, actions: ACTIONS)
  handler = MediaStreamHandler.new(driver.ws)
  driver.start(handler, call_id: call.id, call_sid: "REPLAY#{call.id}", stream_sid: "MZREPLAY#{call.id}")

  sc[:steps].each do |kind, arg|
    break if driver.ended?

    case kind
    when :say then driver.say(arg, ReceptionistVoice.audio(arg))
    when :wait_ours then driver.wait_ours(gap: arg)
    when :music then driver.play_music(arg, ReceptionistVoice.music(arg))
    when :silence then driver.silence(arg)
    end
  end
  driver.wait_end(sc[:end_wait] || (sc[:end] ? 15 : 2))
  sleep 0.5
  driver.stop

  # 途中で止められた録音も「流した」に数える（相手の言葉にかぶせて流したのは不具合）
  played = driver.plays.map(&:key) - ['partial']
  all_played = driver.plays.map(&:key)
  end_action = ACTIONS.map(&:first).find { |k| %i[hangup transfer silent_hangup].include?(k) }
  plays_ok = sc[:plays_prefix] ? all_played.empty? || all_played == ['partial'] || all_played.first(sc[:plays].size) == sc[:plays] : ([sc[:plays]] + Array(sc[:plays_alt])).include?(played)
  ok = plays_ok && end_action == sc[:end] && driver.failures.empty?
  passed += 1 if ok

  out.call
  out.call("#{ok ? 'OK' : 'NG'}  #{num}. #{sc[:name]}")
  out.call("    期待: #{sc[:plays].join(' → ')} → #{sc[:end] || '（通話継続）'}")
  out.call("    実際: #{all_played.join(' → ')} → #{end_action || '（通話継続）'}")
  driver.failures.each { |f| out.call("    ! #{f}") }

  # 時系列（相手の発話・認識結果・判定・こちらの再生）
  rows = driver.timeline.map { |t, who, text| [t, who == :them ? "相手 #{text}" : "こちら[#{text}]"] }
  CallLatencyLog.events(call.id).each do |e|
    x = e['extra'] || {}
    case e['event']
    when 'transcript_final' then rows << [e['mono'], "  認識「#{x['text']}」#{x['doubt'] ? '（途中結果）' : ''}"]
    when 'branch_confirmed' then rows << [e['mono'], "  判定 → #{x['branch_id']}"]
    when 'late_text' then rows << [e['mono'], "  遅れて届いた認識「#{x['text']}」"]
    when 'final_recheck' then rows << [e['mono'], "  確定結果「#{x['text']}」で判定し直し → #{x['branch_id']}"]
    when 'opening_machine' then rows << [e['mono'], "  留守電・自動音声と判定（#{x['branch_id']}）"]
    when 'turn_ignored' then rows << [e['mono'], "  保留中なので無視（#{x['reason']}）"]
    when 'silence_step' then rows << [e['mono'], "  無言#{x['stage']}段階目（#{x['reason']}）"]
    when 'stt_error' then rows << [e['mono'], "  音声認識エラー: #{x['message']}"]
    when 'watchdog' then rows << [e['mono'], '  見張りが発動']
    end
  end
  ACTIONS.each { |kind, info, t| rows << [t, "  操作: #{kind}#{info ? "（#{info}）" : ''}"] }
  t0 = rows.map(&:first).min
  rows.sort_by(&:first).each { |t, text| out.call(format('    %6.2f秒  %s', t - t0, text)) }

  lat = CallLatencyLog.response_samples(call.id)
  out.call("    話し終わり → こちらの返事まで: #{lat.map { |v| "#{(v / 1000.0).round(2)}秒" }.join(', ')}") if lat.any?
end

total = only.any? ? only.size : SCENARIOS.size
out.call
out.call("結果: #{passed}/#{total} 件 OK")
File.write(Rails.root.join('verification/replay/last_result.txt'), lines.join("\n"))
exit(passed == total ? 0 : 1)
