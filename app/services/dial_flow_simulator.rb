# Twilio を使わず、発話列に対する分岐をプログラムで検証する。
class DialFlowSimulator
  Step = Struct.new(:input, :script_key, :hangup, :streak, keyword_init: true)

  def initialize(dial_script, call: nil, llm: false)
    @dial_script = dial_script
    @call = call || build_ephemeral_call
    @llm = llm
    @steps = []
  end

  attr_reader :steps, :call

  def step(text)
    record_key(DialFlowEngine.resolve(text, call: @call, llm: @llm), them: text)
  end

  def timeout
    record_key(DialFlowEngine.on_listen_timeout(@call), them: '')
  end

  def run(utterances)
    Array(utterances).map { |u| step(u) }
  end

  def script_texts
    @steps.map { |s| TwilioService.script_text(s.script_key, @call) }
  end

  private

  def record_key(key, them:)
    hangup = TwilioService.hangup_script?(key)
    us_text = TwilioService.script_text(key, @call)
    @call.remember_context!(them: them, script: key, us: us_text)
    record = Step.new(
      input: them.to_s,
      script_key: key,
      hangup: hangup,
      streak: @call.unknown_streak.to_i
    )
    @steps << record
    record
  end

  def build_ephemeral_call
    Call.new(
      dial_script: @dial_script,
      unknown_streak: 0,
      call_type: 'auto_phone',
      flow_phase: 'talking'
    )
  end
end
