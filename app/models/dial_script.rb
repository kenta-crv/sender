class DialScript < ApplicationRecord
  has_many :dial_utterances, dependent: :destroy
  has_many :dial_faqs, dependent: :destroy
  has_many :dial_unknown_utterances, dependent: :nullify

  validates :name, presence: true

  REPEAT_TEXT = 'もう一度おっしゃっていただけますか。'.freeze
  SMALLTALK_TEXT = 'ご担当の方はいらっしゃいますでしょうか。'.freeze
  CLARIFY_TEXT = '恐れ入ります、少々聞き取りづらかったです。ご担当の方はいらっしゃいますでしょうか。'.freeze
  CLARIFY_ALT_TEXT = '申し訳ございません、うまく聞き取れませんでした。ご担当の方はいらっしゃいますでしょうか。'.freeze
  CLARIFY_SIMPLE_TEXT = 'ご担当の方がいらっしゃればはい、不在でしたら不在とだけお伝えください。'.freeze
  CALLBACK_TEXT = 'それでは、改めてお電話させていただきます。失礼いたします。'.freeze

  SAMPLE_RESPONSE_BANKS = {
    'greeting' => [
      'お電話ありがとうございます。ご担当の方はいらっしゃいますでしょうか。',
      'お世話になっております。ご担当の方はいらっしゃいますでしょうか。',
      '突然のお電話、失礼いたします。ご担当の方はいらっしゃいますでしょうか。'
    ],
    'purpose' => [
      '本日はご案内でお電話しました。続きをお聞きいただけますか。',
      '簡単に概要だけお伝えしたいのですが、少々お時間よろしいでしょうか。',
      'ご担当の方へご案内があり、お電話いたしました。続けてもよろしいでしょうか。'
    ],
    'wait' => [
      '承知しました。そのままお待ちします。',
      'かしこまりました。お待ちしております。',
      'はい、少々お待ちくださいませ。'
    ],
    'smalltalk' => [
      SMALLTALK_TEXT,
      'ありがとうございます。ご担当の方へおつなぎいただけますでしょうか。',
      'お忙しいところ恐れ入ります。ご担当の方はいらっしゃいますでしょうか。'
    ],
    'clarify' => [
      CLARIFY_TEXT,
      'もう一度、ご担当の方はいらっしゃいますでしょうか。'
    ],
    'clarify_alt' => [
      CLARIFY_ALT_TEXT,
      '恐れ入ります。もう一度だけ、ご回答をお願いできますでしょうか。'
    ],
    'clarify_simple' => [
      CLARIFY_SIMPLE_TEXT,
      '簡単で構いません。担当の方がいらっしゃればはい、不在なら不在とお答えください。'
    ],
    'silence_1' => [
      'もしもし？'
    ],
    'silence_2' => [
      'お電話が少し遠いようでして…。ご担当の方はいらっしゃいますでしょうか。'
    ],
    'callback' => [
      CALLBACK_TEXT,
      'おそれいります。改めましてご連絡いたしますので、本日は失礼いたします。'
    ]
  }.freeze

  BANK_EDIT_KEYS = %w[greeting purpose wait smalltalk clarify clarify_alt clarify_simple silence_1 silence_2 callback].freeze

  CONTINUE_KEYS = %w[wait smalltalk faq].freeze
  CONTINUE_LABELS = {
    'wait' => '待ち',
    'smalltalk' => '挨拶・雑談',
    'faq' => 'FAQ'
  }.freeze
  FLOW_KEYS = %w[clarify clarify_alt clarify_simple silence_1 silence_2 transfer].freeze
  FLOW_LABELS = {
    'clarify' => '聞き直し1',
    'clarify_alt' => '聞き直し1別表現',
    'clarify_simple' => '聞き直し2(はい/いいえ)',
    'silence_1' => '無言1(もしもし)',
    'silence_2' => '無言2(電話が遠い)',
    'transfer' => '担当者転送'
  }.freeze
  INTENT_KEYS = (CONTINUE_KEYS + %w[transfer] + Call::AI_STATUS_ITEMS).freeze
  SCRIPT_KEYS = (INTENT_KEYS + %w[greeting repeat purpose callback] + FLOW_KEYS).uniq.freeze
  SCRIPT_LABELS = (
    { 'greeting' => '挨拶', 'repeat' => '聞き直し', 'purpose' => '用件説明', 'callback' => '改めて連絡' }
      .merge(CONTINUE_LABELS)
      .merge(FLOW_LABELS)
      .merge(Call::AI_STATUS_ITEMS.index_by { |label| label })
  ).freeze

  def self.utterance_options
    INTENT_KEYS.map { |key| [SCRIPT_LABELS[key] || key, key] }
  end

  before_validation :fill_default_texts
  before_validation :ensure_sample_banks

  def label_for_select
    "ID #{id}: #{name}"
  end

  def response_banks_hash
    JSON.parse(response_banks.presence || '{}')
  rescue JSON::ParserError
    {}
  end

  def bank_lines_for(key)
    key = key.to_s
    stored = Array(response_banks_hash[key]).map(&:to_s).map(&:strip).reject(&:blank?)
    stored = stored.reject { |line| line.include?('途切れて') }
    stored << 'もう一度、ご担当の方はいらっしゃいますでしょうか。' if key == 'clarify' && stored.size < 2
    return stored if stored.present?

    legacy = legacy_text_for(key)
    lines = (Array(SAMPLE_RESPONSE_BANKS[key]) + [legacy]).compact.map(&:to_s).map(&:strip).reject(&:blank?).uniq
    lines.presence || [REPEAT_TEXT]
  end

  def pick_text_for(key, call: nil)
    key = key.to_s
    if key == 'greeting'
      legacy = greeting_text.to_s.strip
      return legacy if legacy.include?('ご担当')

      return SAMPLE_RESPONSE_BANKS['greeting'].first
    end
    if key == 'wait'
      legacy = wait_text.to_s.strip
      return legacy if legacy.present?
    end
    if key == 'smalltalk'
      return SMALLTALK_TEXT
    end

    lines = bank_lines_for(key)
    return lines.first if lines.size <= 1 || !call.is_a?(Call)

    ctx = call.conversation_context_hash
    last_us = ctx['last_us'].to_s
    candidates = lines.reject { |t| t == last_us }
    candidates = lines if candidates.empty?
    idx = (call.id.to_i + Array(ctx['turns']).size) % candidates.size
    candidates[idx]
  end

  def text_for(key)
    pick_text_for(key)
  end

  def legacy_text_for(key)
    case key.to_s
    when 'greeting'
      greeting_text
    when 'repeat'
      repeat_text.presence || REPEAT_TEXT
    when 'purpose'
      purpose_text
    when 'wait'
      wait_text
    when 'smalltalk'
      smalltalk_text.presence || SMALLTALK_TEXT
    when 'clarify'
      clarify_text.presence || CLARIFY_TEXT
    when 'clarify_alt'
      clarify_alt_text.presence || CLARIFY_ALT_TEXT
    when 'clarify_simple'
      clarify_simple_text.presence || CLARIFY_SIMPLE_TEXT
    when 'callback'
      callback_text.presence || CALLBACK_TEXT
    when 'transfer'
      DialTransferService::THANKS_TEXT
    when 'faq'
      nil
    when *Call::AI_STATUS_ITEMS, *Call.StatuItems
      status_text(key)
    else
      send("#{key}_text")
    end
  rescue NoMethodError
    nil
  end

  def status_text(label)
    status_texts_hash[label.to_s].presence
  end

  def bank_field(key)
    Array(response_banks_hash[key.to_s]).presence || bank_lines_for(key)
  end

  def assign_bank_field(key, raw)
    lines = raw.to_s.split(/\r?\n/).map(&:strip).reject(&:blank?)
    banks = response_banks_hash
    banks[key.to_s] = lines
    self.response_banks = JSON.generate(banks)
  end

  def fill_default_texts
    self.repeat_text = REPEAT_TEXT if repeat_text.blank?
    self.smalltalk_text = SMALLTALK_TEXT if smalltalk_text.blank?
    self.clarify_text = CLARIFY_TEXT if clarify_text.blank?
    self.clarify_alt_text = CLARIFY_ALT_TEXT if clarify_alt_text.blank?
    self.clarify_simple_text = CLARIFY_SIMPLE_TEXT if clarify_simple_text.blank?
    self.callback_text = CALLBACK_TEXT if callback_text.blank?
  end

  def ensure_sample_banks
    banks = response_banks_hash
    changed = false
    SAMPLE_RESPONSE_BANKS.each do |key, samples|
      current = Array(banks[key]).map(&:to_s).map(&:strip).reject(&:blank?)
      next if current.present?

      banks[key] = samples
      changed = true
    end
    self.response_banks = JSON.generate(banks) if changed || response_banks.blank?
  end

  def status_texts_hash
    JSON.parse(status_texts.presence || '{}')
  rescue JSON::ParserError
    {}
  end
end
