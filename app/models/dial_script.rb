class DialScript < ApplicationRecord
  has_many :dial_utterances, dependent: :destroy

  validates :name, presence: true

  REPEAT_TEXT = 'もう一度おっしゃっていただけますか。'.freeze
  CONTINUE_KEYS = %w[purpose wait].freeze
  CONTINUE_LABELS = {
    'purpose' => '用件',
    'wait' => '待ち'
  }.freeze
  SCRIPT_KEYS = (CONTINUE_KEYS + %w[repeat] + Call.StatuItems).freeze
  SCRIPT_LABELS = (
    { 'greeting' => '挨拶', 'repeat' => '聞き直し' }
      .merge(CONTINUE_LABELS)
      .merge(Call.StatuItems.index_by { |label| label })
  ).freeze

  def self.utterance_options
    SCRIPT_KEYS.map { |key| [SCRIPT_LABELS[key] || key, key] }
  end

  before_validation :fill_repeat_text

  def label_for_select
    "ID #{id}: #{name}"
  end

  def text_for(key)
    case key.to_s
    when 'greeting'
      greeting_text
    when 'repeat'
      repeat_text.presence || REPEAT_TEXT
    when 'purpose'
      purpose_text
    when 'wait'
      wait_text
    when *Call.StatuItems
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

  def fill_repeat_text
    self.repeat_text = REPEAT_TEXT if repeat_text.blank?
  end

  def status_texts_hash
    JSON.parse(status_texts.presence || '{}')
  rescue JSON::ParserError
    {}
  end
end
