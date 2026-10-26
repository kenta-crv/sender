require 'test_helper'

class DialFlowSimulatorTest < ActiveSupport::TestCase
  setup do
    @script = DialScript.create!(
      name: 'intent-test',
      greeting_text: 'こんにちは。',
      purpose_text: '本日ご案内です。',
      wait_text: '少々お待ちください。'
    )
    @script.dial_utterances.create!(phrase: '少々お待ち', script_key: 'wait')
    @script.dial_utterances.create!(phrase: '結構です', script_key: 'フロントアウト')
    @script.dial_faqs.create!(
      question: '料金はいくらですか',
      answer: '料金は担当よりご案内します。',
      phrases: ['費用', 'いくら'].to_json
    )
  end

  test 'registered phrase maps to wait without falling to clarify' do
    sim = DialFlowSimulator.new(@script, llm: false)
    step = sim.step('はい、少々お待ちください')

    assert_equal 'wait', step.script_key
    refute step.hangup
    assert_equal 0, step.streak
  end

  test 'greeting smalltalk is handled without clarify loop' do
    sim = DialFlowSimulator.new(@script, llm: false)
    step = sim.step('もしもし')

    assert_equal 'smalltalk', step.script_key
    refute step.hangup
  end

  test 'faq phrase returns faq answer' do
    sim = DialFlowSimulator.new(@script, llm: false)
    step = sim.step('費用について教えてください')

    assert_equal 'faq', step.script_key
    refute step.hangup
    text = TwilioService.script_text(step.script_key, sim.call)
    assert_includes text, '料金は担当よりご案内します'
  end

  test 'unknown falls through three stages then front out hangup' do
    sim = DialFlowSimulator.new(@script, llm: false)
    steps = sim.run(['あいうえお', 'かきくけこ', 'さしすせそ'])

    assert_equal 'smalltalk', steps[0].script_key
    assert_equal 1, steps[0].streak
    refute steps[0].hangup

    assert_equal 'clarify', steps[1].script_key
    assert_equal 2, steps[1].streak
    refute steps[1].hangup

    assert_equal 'フロントアウト', steps[2].script_key
    assert_equal 3, steps[2].streak
    assert steps[2].hangup
  end

  test 'successful intent resets unknown streak' do
    sim = DialFlowSimulator.new(@script, llm: false)
    sim.step('わけのわからない発話')
    assert_equal 1, sim.call.unknown_streak

    step = sim.step('少々お待ちを')
    assert_equal 'wait', step.script_key
    assert_equal 0, step.streak
  end

  test 'rejection phrase hangs up with front out' do
    sim = DialFlowSimulator.new(@script, llm: false)
    step = sim.step('結構です')

    assert_equal 'フロントアウト', step.script_key
    assert step.hangup
  end

  test 'self identification is the person and transfers' do
    sim = DialFlowSimulator.new(@script, llm: false)
    step = sim.step('私です。')

    assert_equal 'transfer', step.script_key
    refute step.hangup
    assert_equal DialTransferService::THANKS_TEXT, TwilioService.script_text(step.script_key, sim.call)
  end

  test 'transfer phrase maps to transfer' do
    sim = DialFlowSimulator.new(@script, llm: false)
    step = sim.step('お電話代わりました')

    assert_equal 'transfer', step.script_key
    refute step.hangup
    assert_equal DialTransferService::THANKS_TEXT, TwilioService.script_text(step.script_key, sim.call)
  end

  test 'absent phrase maps to 担当者不在' do
    sim = DialFlowSimulator.new(@script, llm: false)
    step = sim.step('担当は不在にしております')

    assert_equal '担当者不在', step.script_key
    assert step.hangup
  end

  test 'voicemail maps to 着信不在' do
    sim = DialFlowSimulator.new(@script, llm: false)
    step = sim.step('留守番電話です。メッセージをどうぞ')

    assert_equal '着信不在', step.script_key
    assert step.hangup
  end

  test 'persisted call logs unknown utterances' do
    customer = Customer.create!(company: '株式会社検証', tel: '03-1111-2222')
    call = Call.create!(
      customer: customer,
      dial_script: @script,
      call_type: 'auto_phone',
      flow_phase: 'talking',
      unknown_streak: 0
    )

    key = DialFlowEngine.resolve('意味不明な発話XYZ', call: call, llm: false)
    assert_equal 'smalltalk', key
    assert_equal 1, call.reload.unknown_streak
    log = DialUnknownUtterance.last
    assert_equal call.id, log.call_id
    assert_equal @script.id, log.dial_script_id
    assert_equal '意味不明な発話XYZ', log.transcript
    assert_equal 1, log.streak
  end

  test 'choose_script delegates to flow engine' do
    call = Call.new(dial_script: @script, unknown_streak: 0)
    assert_equal 'smalltalk', TwilioService.choose_script('こんにちは', call: call, llm: false)
  end

  test 'conversation context is remembered across turns' do
    sim = DialFlowSimulator.new(@script, llm: false)
    sim.step('もしもし')
    ctx = sim.call.conversation_context_hash

    assert_equal 'smalltalk', ctx['last_script']
    assert_equal 1, Array(ctx['turns']).size
  end

  test 'response bank avoids repeating the same clarify line' do
    @script.assign_bank_field(
      'clarify',
      [
        '聞き直しAです。ご担当の方はいらっしゃいますでしょうか。',
        '聞き直しBです。ご担当の方はいらっしゃいますでしょうか。'
      ].join("\n")
    )
    @script.save!
    call = Call.new(id: 1, dial_script: @script, unknown_streak: 0)
    first = TwilioService.script_text('clarify', call)
    call.remember_context!(them: 'あいうえお', script: 'clarify', us: first)
    second = TwilioService.script_text('clarify', call)

    assert_includes [first, second], '聞き直しAです。ご担当の方はいらっしゃいますでしょうか。'
    assert_includes [first, second], '聞き直しBです。ご担当の方はいらっしゃいますでしょうか。'
    refute_equal first, second
  end

  test 'greeting plays the full front desk ask not the first sentence only' do
    @script.update!(greeting_text: 'お電話ありがとうございます。')
    @script.assign_bank_field('greeting', "お電話ありがとうございます。\n別の短い挨拶")
    @script.save!
    call = Call.new(id: 1, dial_script: @script)
    text = TwilioService.script_text('greeting', call)

    assert_includes text, 'ご担当'
    refute_equal 'お電話ありがとうございます。', text
  end

  test 'yes after greeting is wait not purpose' do
    sim = DialFlowSimulator.new(@script, llm: false)
    step = sim.step('はい')

    assert_equal 'wait', step.script_key
    refute step.hangup
  end

  test 'twiml says the full greeting then listens' do
    customer = Customer.create!(company: '株式会社検証', tel: '03-1111-2222')
    call = Call.create!(
      customer: customer,
      dial_script: @script,
      call_type: 'auto_phone',
      flow_phase: 'talking'
    )
    xml = TwimlBuilder.new.voice_response(call).to_s

    assert_includes xml, 'ご担当'
    assert xml.index('<Say') < xml.index('<Gather'), xml
    refute_match(/<Gather[^>]*>\s*<Say/, xml)
  end

  test 'new dial script gets sample response banks' do
    script = DialScript.create!(name: 'bank-seed-test')
    banks = script.response_banks_hash

    assert banks['smalltalk'].size >= 2
    assert banks['clarify'].size >= 2
  end

  test 'front desk through path from greeting to transfer hangup and timeout' do
    @script.update!(
      greeting_text: 'お電話ありがとうございます。ご担当の方はいらっしゃいますでしょうか。',
      wait_text: '承知しました。そのままお待ちします。'
    )
    call = Call.new(id: 1, dial_script: @script)
    greeting = TwilioService.script_text('greeting', call)
    assert_includes greeting, 'お電話ありがとうございます'
    assert_includes greeting, 'ご担当'
    refute_includes greeting, 'ご案内'

    sim = DialFlowSimulator.new(@script, llm: false)
    moshi = sim.step('もしもし')
    assert_equal 'smalltalk', moshi.script_key
    assert_includes TwilioService.script_text('smalltalk', sim.call), 'ご担当'

    hai = sim.step('はい')
    assert_equal 'wait', hai.script_key
    refute hai.hangup
    assert_includes TwilioService.script_text('wait', sim.call), 'お待ち'
    refute_includes TwilioService.script_text('wait', sim.call), 'ご案内'

    xfer = sim.step('お電話代わりました')
    assert_equal 'transfer', xfer.script_key
    refute xfer.hangup
    assert_equal DialTransferService::THANKS_TEXT, TwilioService.script_text('transfer', sim.call)

    absent = DialFlowSimulator.new(@script, llm: false).step('担当は不在です')
    assert_equal '担当者不在', absent.script_key
    assert absent.hangup

    front = DialFlowSimulator.new(@script, llm: false).step('結構です')
    assert_equal 'フロントアウト', front.script_key
    assert front.hangup

    vm = DialFlowSimulator.new(@script, llm: false).step('留守番電話です。メッセージをどうぞ')
    assert_equal '着信不在', vm.script_key
    assert vm.hangup

    timed = DialFlowSimulator.new(@script, llm: false)
    assert_equal 'smalltalk', timed.timeout.script_key
    assert_equal 'clarify', timed.timeout.script_key
    last = timed.timeout
    assert_equal 'フロントアウト', last.script_key
    assert last.hangup

    customer = Customer.create!(company: '通し検証', tel: '03-2222-3333')
    live = Call.create!(
      customer: customer,
      dial_script: @script,
      call_type: 'auto_phone',
      flow_phase: 'talking'
    )
    greet_xml = TwimlBuilder.new.voice_response(live).to_s
    assert_includes greet_xml, 'ご担当'
    refute_includes greet_xml, 'ご案内'
    assert greet_xml.index('<Say') < greet_xml.index('<Gather')
    refute_match(/<Gather[^>]*>\s*<Say/, greet_xml)

    wait_xml = TwimlBuilder.new.gather_script_response(live, 'wait', hangup: false).to_s
    refute_includes wait_xml, '<Conference'
    assert_includes wait_xml, '<Gather'

    xfer_xml = TwimlBuilder.new.gather_script_response(live, 'transfer', hangup: false).to_s
    assert_includes xfer_xml, DialTransferService::THANKS_TEXT
    assert_includes xfer_xml, 'beep="false"'
    assert_includes xfer_xml, '<Conference'
    refute_includes xfer_xml, '<Gather'
    refute_includes xfer_xml, 'waitUrl="">'

    hang_xml = TwimlBuilder.new.gather_script_response(live, 'フロントアウト', hangup: true).to_s
    assert_includes hang_xml, '<Hangup'
    refute_includes hang_xml, '<Gather'
  end
end
