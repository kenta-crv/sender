# 意図分類の結果を script_key に落とし、分類失敗時だけ段階フォールバックする。
class DialFlowEngine
  MAX_UNKNOWN_STREAK = 3

  def self.resolve(text, call:, llm: true)
    text = TwilioService.utf8_speech(text)
    pack = call.is_a?(Call) ? call.dial_script : nil

    if text.blank?
      return apply_failure!(call, transcript: text, path: 'blank')
    end

    result = DialIntentClassifier.classify(
      text,
      pack: pack,
      llm: llm,
      context: call.is_a?(Call) ? call.conversation_context_hash : nil
    )
    if result.intent.present? && result.intent != 'unknown'
      reset_streak!(call)
      if result.intent == 'faq' && result.faq_id && call.is_a?(Call)
        write_call_attrs!(call, pending_faq_id: result.faq_id)
      end
      return result.intent
    end

    apply_failure!(call, transcript: text, path: result.path.presence || 'unknown')
  end

  def self.on_listen_timeout(call)
    apply_failure!(call, transcript: '', path: 'timeout')
  end

  def self.fallback_key_for(streak, call = nil)
    case streak.to_i
    when 1
      'smalltalk'
    when 2
      'clarify'
    else
      'フロントアウト'
    end
  end

  def self.apply_failure!(call, transcript:, path:)
    streak = 1
    if call.is_a?(Call)
      streak = call.unknown_streak.to_i + 1
      write_call_attrs!(call, unknown_streak: streak)
    end

    key = fallback_key_for(streak, call)
    log_unknown!(call, transcript: transcript, path: path, fallback_key: key, streak: streak)
    key
  end

  def self.reset_streak!(call)
    return unless call.is_a?(Call)
    return if call.unknown_streak.to_i.zero?

    write_call_attrs!(call, unknown_streak: 0)
  end

  def self.write_call_attrs!(call, attrs)
    if call.persisted?
      call.update(attrs)
    else
      call.assign_attributes(attrs)
    end
  end

  def self.note_unclear!(call, transcript:, path:)
    apply_failure!(call, transcript: transcript, path: path)
  end

  def self.note_clear!(call)
    reset_streak!(call)
  end

  def self.log_unknown!(call, transcript:, path:, fallback_key:, streak:)
    return unless call.is_a?(Call) && call.persisted?

    DialUnknownUtterance.create!(
      dial_script_id: call.dial_script_id,
      call_id: call.id,
      transcript: transcript.to_s,
      classifier_path: path.to_s,
      fallback_key: fallback_key.to_s,
      streak: streak
    )
  rescue => e
    Rails.logger.error("[DialFlowEngine] unknown log error: #{e.message}")
  end
  private_class_method :apply_failure!, :reset_streak!, :write_call_attrs!, :log_unknown!
end
