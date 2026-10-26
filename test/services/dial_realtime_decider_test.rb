require 'test_helper'
require_relative '../../lib/mulaw'
require_relative '../../lib/utterance_vad'
require_relative '../../lib/bidirectional_call_session'

class DialRealtimeDeciderTest < ActiveSupport::TestCase
  setup do
    DialPlaybackCache.reset!
    @script = DialScript.create!(
      name: 'realtime-nuance',
      greeting_text: 'お電話ありがとうございます。ご担当の方はいらっしゃいますでしょうか。'
    )
    rows = %w[greeting purpose wait smalltalk clarify clarify_alt clarify_simple callback transfer repeat 着信不在 フロントアウト 担当者不在 電話不通].map do |key|
      { branch_id: key, recording_id: key, transfer: key == 'transfer' }
    end
    DialPlaybackCache.prime!(@script.id, rows)
    @call = Call.new(dial_script: @script, dial_script_id: @script.id)
  end

  teardown do
    DialPlaybackCache.reset!
  end

  test '言い換え、否定、遠回しは完全一致なしで分岐する' do
    cases = {
      'ちょっと待ってもらえますか' => ['wait', false],
      '確認してから担当者をお呼びしますね' => ['wait', false],
      '担当を呼んできますので、そのままお待ちいただけますか' => ['wait', false],
      '担当の者は今席を外しております' => ['担当者不在', false],
      'いや、今回は結構です' => ['フロントアウト', false],
      '必要ないので大丈夫です' => ['フロントアウト', false],
      'どういったご用件でしょうか' => ['purpose', false],
      'また改めてご連絡いただけますか' => ['callback', false],
      '本人は席にいないみたいですね' => ['担当者不在', false],
      '電話代わりました、私が担当です' => ['transfer', true],
      '今はちょっと難しいかもしれません' => ['clarify', false],
      '担当ではないのでわかりかねます' => ['clarify', false]
    }

    cases.each do |text, expected|
      decision = DialRealtimeDecider.decide(text, call: @call, llm: false)
      assert_equal expected[0], decision.branch_id, text
      assert_equal expected[1], decision.transfer, text
      refute_includes decision.recording_id, '://', text
    end
  end

  test 'はいだけは聞き返しで、聞き直しのあとのはいは待ちになる' do
    alone = DialRealtimeDecider.decide('はい', call: @call, llm: false)
    assert_equal 'clarify', alone.branch_id
    assert alone.ambiguous
    refute alone.transfer

    @call.conversation_context = JSON.generate('last_script' => 'clarify_simple', 'turns' => [])
    answered = DialRealtimeDecider.decide('はい', call: @call, llm: false)
    assert_equal 'wait', answered.branch_id
    refute answered.transfer
  end

  test 'モデルが転送と返しても否定と認識疑いとURLは転送しない' do
    forced = lambda do |_text, _call|
      { 'branch_id' => 'transfer', 'recording_id' => 'transfer', 'transfer' => true }
    end
    negated = DialRealtimeDecider.decide('いや、今回は結構です', call: @call, llm: forced)
    assert_equal 'フロントアウト', negated.branch_id
    refute negated.transfer

    unsure = DialRealtimeDecider.decide('私が担当です', call: @call, stt_confidence: 0.2, llm: forced)
    assert_equal 'clarify', unsure.branch_id
    refute unsure.transfer

    linked = lambda do |_text, _call|
      { 'branch_id' => 'wait', 'recording_id' => 'https://evil.example/a.mp3', 'transfer' => false }
    end
    rejected = DialRealtimeDecider.decide('ちょっと待ってください', call: @call, llm: linked)
    assert_equal 'clarify', rejected.recording_id
    refute_includes rejected.recording_id, 'http'
  end

  test '原稿ID 1だけが双方向ストリームになる' do
    xml = TwimlBuilder.new.connect_stream_response(Call.new(id: 1, dial_script_id: 1), 'wss://example.test/media-stream').to_s
    assert_includes xml, '<Connect>'
    assert_includes xml, '<Stream'
    assert_includes xml, 'bidirectional'
    refute_includes xml, '<Gather'

    assert TwilioService.bidirectional_call?(Call.new(dial_script_id: 1))
    refute TwilioService.bidirectional_call?(Call.new(dial_script_id: 2))
  end

  test '無音で発話終了を検知する' do
    vad = UtteranceVad.new
    speech = Mulaw.tone(1600, amplitude: 12000)
    silence = Mulaw.silence(4000)
    assert vad.feed(speech + silence)
  end

  test '発話終了のあとだけ録音の最初のフレームを送る' do
    CallLatencyLog.clear!(4242)
    socket = FakeMediaSocket.new
    decider = CountingDecider.new
    call = Call.new(id: 4242, dial_script_id: @script.id)
    session = BidirectionalCallSession.new(
      socket,
      call_id: 4242,
      call_sid: 'CA_TEST',
      stream_sid: 'MZ_TEST',
      call: call,
      persist: false,
      greet: false,
      decider: decider
    )

    session.on_interim('ちょっと待って', 0.0)
    assert_empty socket.sent
    assert_equal 0, decider.count

    session.on_final('ちょっと待ってもらえますか', 0.9)
    assert_empty socket.sent

    session.feed(Mulaw.tone(1600, amplitude: 12000) + Mulaw.silence(4000))
    session.wait_idle(3)

    assert decider.count >= 1
    assert socket.sent.any? { |frame| frame.include?('"event":"media"') }
    samples = CallLatencyLog.response_samples(4242)
    assert_equal 1, samples.size
    assert_operator samples.first, :<, 1000
    puts "\n[ローカル計測] #{CallLatencyLog.report(4242)}"
  end
end

class FakeMediaSocket
  attr_reader :sent

  def initialize
    @sent = []
  end

  def send(data)
    @sent << data
  end
end

class CountingDecider
  attr_reader :count

  def initialize
    @count = 0
    @mutex = Mutex.new
  end

  def decide(_text, call:, stt_confidence: nil)
    @mutex.synchronize { @count += 1 }
    DialRealtimeDecider::Decision.new(
      branch_id: 'wait',
      recording_id: 'wait',
      transfer: false,
      path: 'test',
      ambiguous: false
    )
  end
end
