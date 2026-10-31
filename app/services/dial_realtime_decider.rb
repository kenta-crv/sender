# 意味と会話の流れで分岐する。完全一致では選ばない。
# AIが返せるのは相手の発話の分類だけ。録音への対応はコードが決める。URLは受け取らない。
class DialRealtimeDecider
  Decision = Struct.new(:branch_id, :recording_id, :transfer, :path, :ambiguous, keyword_init: true)

  # 分類名 → 録音ID。greeting / repeat / clarify系はここには置かない。不明だけ clarify。
  CATEGORY_BRANCH = {
    '本人' => 'transfer',
    '取り次ぎ' => 'wait',
    '不在' => '担当者不在',
    '断り' => 'フロントアウト',
    '改めて' => 'callback',
    '用件確認' => 'purpose',
    '挨拶' => 'smalltalk',
    '留守電' => '着信不在',
    '不明' => 'clarify'
  }.freeze

  VOICEMAIL_RE = /留守番|伝言|メッセージをどうぞ|発信音の後/.freeze
  ABSENT_RE = /いません|いない|おりません|不在|席を外|外出|留守にして/.freeze
  REFUSAL_RE = /結構|不要|いらない|いらな|お断り|興味(?:は)?ありません|必要(?:は)?ない|必要ありません|間に合/.freeze
  CALLBACK_RE = /改めて|折り返し|後ほど|またご連絡|また連絡/.freeze
  TRANSFER_RE = /代わりました|かわりました|担当(?:の者|者)?です|担当でございます|私が担当|本人です|電話に出ました/.freeze
  WAIT_RE = /待って|待ても|お待ち|待ちください|確認して|確認いたし|確認します|呼んで|呼びます|呼んでき|取り次|つなぎます|繋ぎます|お繋ぎします|おつなぎします|そのまま/.freeze
  PURPOSE_RE = /用件|どういった|どのような|どちら様/.freeze
  SMALLTALK_RE = /もしもし|こんにちは|こんばんは|おはよう|お世話になって|失礼します/.freeze
  NEGATION_RE = /いません|いない|おりません|不在|結構|不要|いらない|お断り|ではない|じゃない|違います|必要(?:は)?ない|必要ありません|間に合/.freeze
  SOFT_RE = /かもしれません|かもしれない|難しい|厳しい|検討します|考えておきます/.freeze
  # 「ご担当の方は」に対して、自分が担当だと答える言い方（10/10 の実通話「私です。」）
  SELF_ID_RE = /(?:私|わたし|わたくし|僕|ぼく|自分)(?:です|でございます|が担当|が承ります)|本人です|担当(?:の者|者)?(?:です|でございます)|担当の.{1,8}(?:です|でございます)/.freeze
  SHORT_RE = /\A(?:はい|ええ|うん|あー|えーと)(?:です|。)?\z/.freeze

  def self.decide(text, call:, stt_confidence: nil, llm: :auto)
    script_id = call&.dial_script_id
    allow = DialPlaybackCache.allowlist(script_id)
    cleaned = TwilioService.utf8_speech(text)
    context = call.is_a?(Call) ? call.conversation_context_hash : {}

    if cleaned.blank? || recognition_doubt?(stt_confidence)
      return safe_decision(allow, path: cleaned.blank? ? 'blank' : 'recognition_doubt')
    end

    raw = request_judgment(cleaned, call, context, llm)
    decision = validate(raw, allow)
    if raw.is_a?(Hash) && raw['ambiguous'] == true && decision.path == 'allowed'
      decision.ambiguous = true
    end
    decision = block_wrong_transfer(decision, cleaned, allow)
    apply_context_short_reply(decision, cleaned, context, allow)
  end

  def self.recognition_doubt?(confidence)
    # 電話音声は確信度が低めに出るため、明らかに怪しいときだけ聞き返す
    value = confidence.to_f
    value.positive? && value < 0.3
  end

  def self.request_judgment(text, call, context, llm)
    if llm.respond_to?(:call)
      judged = llm.call(text, call)
      return judged if judged.is_a?(Hash) && judged['branch_id'].present?
    elsif llm == :auto && DialLlmClient.enabled?
      judged = llm_judgment(text, call, context)
      return judged if judged.is_a?(Hash) && judged['branch_id'].present?
    end

    local_nuance(text, context)
  end

  def self.llm_judgment(text, call, context)
    context_lines = []
    context_lines << "話題: #{context['topic']}" if context['topic'].present?
    Array(context['turns']).last(4).each do |turn|
      context_lines << "相手: #{turn['them']}"
      context_lines << "こちら[#{turn['script']}]: #{turn['us']}"
    end
    system = <<~PROMPT
      あなたは電話の相手の発話を分類します。録音の名前は返さないでください。
      返す分類は次の9つだけです。
      - 本人: 相手が担当者本人として出た。電話を代わって出たという言葉がある、または「ご担当の方は」と聞かれて「私です」「私が担当です」と自分のことだと答えた。会社名を名乗っただけでは本人ではない。
      - 取り次ぎ: これから呼ぶ、つなぐ、待ってほしい、または担当者がいると答えた。「つなぎます」「代わります」は本人ではなく取り次ぎ。
      - 不在: 担当者が今いない。休み、出張、会議、外出、他の電話、テレワーク、直帰など。
      - 断り: 取り次がない、または必要ない。
      - 改めて: かけ直してほしい、時間を指定された、または折り返すと言われた。
      - 用件確認: 用件、会社名、関係を聞かれた。
      - 挨拶: 呼びかけや挨拶、または会社名・自分の名前を名乗っただけ（「はい、〇〇でございます」「〇〇です」「もしもし」）で、取り次ぎも断りも不在もない。
      - 留守電: 留守番電話や自動音声の案内。
      - 不明: 上のどれにも当てはまらない、または聞き取りが怪しい。
      迷ったときは「本人」より「取り次ぎ」を選ぶ。
      迷ったときは不在・断り・改めて・留守電より「不明」を選ぶ。
      JSONのみ: {"category":"..."}
    PROMPT
    user = <<~USER
      直前の文脈:
      #{context_lines.presence || '(なし)'}
      確定した発話: #{text}
    USER
    data = DialLlmClient.chat_json(system: system, user: user, temperature: 0.0, read_timeout: 2, open_timeout: 1)
    return nil unless data.is_a?(Hash)

    category = data['category'].to_s.strip
    branch_id = branch_for_category(category, DialPlaybackCache.allowlist(call&.dial_script_id))
    return nil if branch_id.blank?

    # 取り次ぎを経ずに「本人」になるのは、自分が担当だとはっきり言ったときだけ
    if category == '本人' && branch_id == 'transfer' && !passed_through_wait?(context) && !text.to_s.match?(SELF_ID_RE)
      branch_id = 'clarify'
    end

    payload(branch_id, ambiguous: category == '不明')
  rescue => e
    Rails.logger.error("[DialRealtimeDecider] llm error: #{e.message}")
    nil
  end

  def self.passed_through_wait?(context)
    return false unless context.is_a?(Hash)
    return true if context['last_script'].to_s == 'wait'

    Array(context['turns']).any? { |turn| turn.is_a?(Hash) && turn['script'].to_s == 'wait' }
  end

  def self.branch_for_category(category, allow)
    branch_id = CATEGORY_BRANCH[category.to_s.strip]
    return nil unless branch_id
    return branch_id if Array(allow).any? { |entry| entry.branch_id == branch_id && entry.recording_id == branch_id }

    'clarify'
  end

  def self.local_nuance(text, context)
    compact = text.to_s.gsub(/[\s　。、！？!?,，]/, '')
    last = context.is_a?(Hash) ? context['last_script'].to_s : ''

    if last == 'clarify_simple'
      return payload('wait') if compact.match?(/\Aはい|います|おります/)
      return payload('担当者不在') if compact.match?(ABSENT_RE)
    end

    return payload('着信不在') if compact.match?(VOICEMAIL_RE)
    return payload('担当者不在') if compact.match?(ABSENT_RE)
    return payload('フロントアウト') if compact.match?(REFUSAL_RE)
    return payload('callback') if compact.match?(CALLBACK_RE)
    return payload('clarify', ambiguous: true) if compact.match?(SHORT_RE)
    return payload('transfer') if compact.match?(TRANSFER_RE) && !compact.match?(NEGATION_RE)
    return payload('wait') if compact.match?(WAIT_RE)
    return payload('purpose') if compact.match?(PURPOSE_RE)
    return payload('smalltalk') if compact.match?(SMALLTALK_RE)
    return payload('clarify', ambiguous: true) if compact.match?(SOFT_RE)

    payload('clarify', ambiguous: true)
  end

  def self.validate(raw, allow)
    data = raw.is_a?(Hash) ? raw : {}
    branch_id = data['branch_id'].to_s
    recording_id = data['recording_id'].to_s
    return safe_decision(allow, path: 'invalid') if recording_id.blank? || recording_id.include?('://') || recording_id.include?('/')

    row = allow.find { |entry| entry.recording_id == recording_id && entry.branch_id == branch_id }
    return safe_decision(allow, path: 'not_allowed') unless row

    transfer = data['transfer'] == true || data['transfer'].to_s == 'true'
    return safe_decision(allow, path: 'transfer_mismatch') if transfer != row.transfer

    Decision.new(
      branch_id: row.branch_id,
      recording_id: row.recording_id,
      transfer: row.transfer,
      path: 'allowed',
      ambiguous: false
    )
  end

  def self.block_wrong_transfer(decision, text, allow)
    return decision unless decision.transfer
    return decision unless text.to_s.gsub(/[\s　]/, '').match?(NEGATION_RE)

    replacement = validate(local_nuance(text, {}), allow)
    replacement = safe_decision(allow, path: 'negation') if replacement.transfer || replacement.branch_id == 'transfer'
    replacement.path = 'negation'
    replacement.transfer = false
    replacement.ambiguous = replacement.branch_id == 'clarify'
    replacement
  end

  def self.apply_context_short_reply(decision, text, context, allow)
    return decision unless decision.ambiguous

    last = context.is_a?(Hash) ? context['last_script'].to_s : ''
    compact = text.to_s.gsub(/[\s　。、]/, '')
    return decision unless last == 'clarify_simple' && compact.match?(/\Aはい/)

    validate(payload('wait'), allow)
  end

  def self.safe_decision(allow, path:)
    row = allow.find { |entry| entry.recording_id == 'clarify' } || allow.find { |entry| entry.transfer == false }
    if row
      Decision.new(branch_id: row.branch_id, recording_id: row.recording_id, transfer: false, path: path, ambiguous: true)
    else
      Decision.new(branch_id: 'clarify', recording_id: 'clarify', transfer: false, path: path, ambiguous: true)
    end
  end

  def self.payload(branch_id, ambiguous: false)
    {
      'branch_id' => branch_id,
      'recording_id' => branch_id,
      'transfer' => branch_id == 'transfer',
      'ambiguous' => ambiguous
    }
  end
  private_class_method :request_judgment, :llm_judgment, :passed_through_wait?, :branch_for_category, :local_nuance, :validate,
                       :block_wrong_transfer, :apply_context_short_reply, :safe_decision, :payload
end
