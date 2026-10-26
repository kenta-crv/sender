# 意図分類: ルール → 埋め込み類似度 → LLM（ラベルのみ）
class DialIntentClassifier
  Result = Struct.new(:intent, :path, :confidence, :faq_id, keyword_init: true)

  EMBED_THRESHOLD = 0.78
  SMALLTALK_PATTERNS = [
    /こんにちは/,
    /こんばんは/,
    /おはよう/,
    /もしもし/,
    /お世話になって/,
    /失礼(?:いた)?します/
  ].freeze
  TRANSFER_PATTERNS = [
    /お電話(?:代わり|かわり)ました/,
    /電話(?:代わり|かわり)ました/,
    /代わりました/,
    /かわりました/,
    /担当(?:の|者)?(?:です|でございます)/,
    /(?:私|わたし|わたくし|僕|ぼく|本人|自分)です/,
    /私が担当/,
    /わたくしが担当/,
    /おつなぎ(?:いた|し)ました/,
    /お繋ぎ(?:いた|し)ました/
  ].freeze
  ABSENT_PATTERNS = [
    /不在/,
    /おりません/,
    /いません/,
    /いないです/,
    /席を外/,
    /出かけて/,
    /留守にして/
  ].freeze
  FRONT_OUT_PATTERNS = [
    /結構です/,
    /必要ありません/,
    /間に合って/,
    /いらない/,
    /大丈夫です/,
    /お断り/,
    /不要です/,
    /興味(?:は)?ありません/
  ].freeze
  VOICEMAIL_PATTERNS = [
    /留守番/,
    /伝言を/,
    /メッセージをどうぞ/,
    /発信音の後に/,
    /ピーという音の後/,
    /ただいま電話に出ることが/,
    /録音(?:して|を)/,
    /ガラケー/
  ].freeze
  WAIT_PATTERNS = [
    /少々お待ち/,
    /お待ちください/,
    /お待ちを/,
    /確認(?:して|いた)します/,
    /取り次/,
    /代わります/,
    /かわります/,
    /おつなぎします/,
    /お繋ぎします/,
    /\Aはい/,
    /いらっしゃいます/,
    /おります/,
    /います(?:よ|ね)?\z/
  ].freeze

  def self.classify(text, pack: nil, llm: true, context: nil)
    text = TwilioService.utf8_speech(text)
    return Result.new(intent: 'unknown', path: 'blank', confidence: 0.0, faq_id: nil) if text.blank?

    builtin = match_builtin(text)
    return builtin if builtin

    rule = match_rules(text, pack)
    return rule if rule

    embed = match_embedding(text, pack)
    return embed if embed

    return match_llm(text, pack, context: context) if llm

    Result.new(intent: 'unknown', path: 'none', confidence: 0.0, faq_id: nil)
  end

  def self.match_builtin(text)
    if VOICEMAIL_PATTERNS.any? { |re| text.match?(re) }
      return Result.new(intent: '着信不在', path: 'voicemail', confidence: 1.0, faq_id: nil)
    end
    if TRANSFER_PATTERNS.any? { |re| text.match?(re) }
      return Result.new(intent: 'transfer', path: 'transfer', confidence: 1.0, faq_id: nil)
    end
    if ABSENT_PATTERNS.any? { |re| text.match?(re) }
      return Result.new(intent: '担当者不在', path: 'absent', confidence: 1.0, faq_id: nil)
    end
    if FRONT_OUT_PATTERNS.any? { |re| text.match?(re) }
      return Result.new(intent: 'フロントアウト', path: 'front_out', confidence: 1.0, faq_id: nil)
    end
    if WAIT_PATTERNS.any? { |re| text.match?(re) }
      return Result.new(intent: 'wait', path: 'wait', confidence: 0.95, faq_id: nil)
    end
    nil
  end

  def self.match_rules(text, pack)
    if pack
      pack.dial_utterances.select { |u| u.phrase.present? }.sort_by { |u| -u.phrase.size }.each do |utterance|
        next unless text.include?(utterance.phrase)

        intent = utterance.script_key.to_s
        next unless DialScript::INTENT_KEYS.include?(intent)

        return Result.new(intent: intent, path: 'rule', confidence: 1.0, faq_id: nil)
      end

      pack.dial_faqs.each do |faq|
        candidates = [faq.question] + faq.phrase_list
        if candidates.any? { |p| p.present? && text.include?(p) }
          return Result.new(intent: 'faq', path: 'rule', confidence: 1.0, faq_id: faq.id)
        end
      end
    end

    if SMALLTALK_PATTERNS.any? { |re| text.match?(re) }
      return Result.new(intent: 'smalltalk', path: 'rule', confidence: 0.9, faq_id: nil)
    end

    nil
  end

  def self.match_embedding(text, pack)
    return nil unless pack
    return nil unless DialLlmClient.enabled?

    query = DialLlmClient.embed(text)
    return nil if query.blank?

    best = nil
    best_score = EMBED_THRESHOLD

    pack.dial_utterances.each do |utterance|
      vec = utterance_embedding(utterance)
      next if vec.blank?

      score = DialLlmClient.cosine(query, vec)
      next if score < best_score

      intent = utterance.script_key.to_s
      next unless DialScript::INTENT_KEYS.include?(intent)

      best_score = score
      best = Result.new(intent: intent, path: 'embedding', confidence: score, faq_id: nil)
    end

    pack.dial_faqs.each do |faq|
      vec = faq.embedding_vector || DialLlmClient.embed(faq.question)
      next if vec.blank?

      score = DialLlmClient.cosine(query, vec)
      next if score < best_score

      best_score = score
      best = Result.new(intent: 'faq', path: 'embedding', confidence: score, faq_id: faq.id)
    end

    best
  rescue => e
    Rails.logger.error("[DialIntentClassifier] embedding error: #{e.message}")
    nil
  end

  def self.utterance_embedding(utterance)
    return nil if utterance.embedding.blank?

    JSON.parse(utterance.embedding)
  rescue JSON::ParserError
    nil
  end

  def self.match_llm(text, pack, context: nil)
    return Result.new(intent: 'unknown', path: 'llm_skipped', confidence: 0.0, faq_id: nil) unless DialLlmClient.enabled?

    labels = DialScript::INTENT_KEYS
    faq_lines = []
    if pack
      pack.dial_faqs.limit(30).each do |faq|
        faq_lines << "- id=#{faq.id}: #{faq.question}"
      end
    end

    context_lines = []
    if context.is_a?(Hash)
      context_lines << "話題: #{context['topic']}" if context['topic'].present?
      Array(context['turns']).last(3).each do |turn|
        context_lines << "相手: #{turn['them']}"
        context_lines << "こちら[#{turn['script']}]: #{turn['us']}"
      end
    end

    system = <<~PROMPT
      あなたは電話応対の意図分類器です。自由文は生成せず、次の意図ラベルのいずれかにだけ分類してください。
      直前の会話文脈がある場合は、それを踏まえてラベルを選んでください。
      許可ラベル: #{labels.join(', ')}, unknown
      FAQがある場合、該当すれば intent を faq にし faq_id を数値で返してください。
      どれにも当てはまらなければ unknown にしてください。
      JSONのみ: {"intent":"...","faq_id":null,"confidence":0.0}
    PROMPT

    user = <<~USER
      直前の文脈:
      #{context_lines.presence || '(なし)'}
      発話: #{text}
      FAQ一覧:
      #{faq_lines.presence || '(なし)'}
    USER

    json = DialLlmClient.chat_json(system: system, user: user, temperature: 0.0)
    return Result.new(intent: 'unknown', path: 'llm_failed', confidence: 0.0, faq_id: nil) if json.blank?

    intent = json['intent'].to_s
    faq_id = json['faq_id']
    confidence = json['confidence'].to_f
    allowed = DialScript::INTENT_KEYS + ['unknown']
    unless allowed.include?(intent)
      return Result.new(intent: 'unknown', path: 'llm_invalid', confidence: 0.0, faq_id: nil)
    end

    if intent == 'faq'
      faq_id = faq_id.to_i
      faq_id = nil if faq_id <= 0
      unless faq_id && pack&.dial_faqs&.exists?(id: faq_id)
        return Result.new(intent: 'unknown', path: 'llm_faq_miss', confidence: confidence, faq_id: nil)
      end
    else
      faq_id = nil
    end

    Result.new(intent: intent, path: 'llm', confidence: confidence, faq_id: faq_id)
  rescue => e
    Rails.logger.error("[DialIntentClassifier] llm error: #{e.message}")
    Result.new(intent: 'unknown', path: 'llm_error', confidence: 0.0, faq_id: nil)
  end
  private_class_method :match_builtin, :match_rules, :match_embedding, :match_llm, :utterance_embedding
end
