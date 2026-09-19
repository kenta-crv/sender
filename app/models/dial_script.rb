class DialScript < ApplicationRecord
  has_many :dial_utterances, dependent: :destroy

  validates :name, presence: true

  SCRIPT_KEYS = %w[greeting purpose wait absent rejection no_human repeat closing].freeze
  SCRIPT_LABELS = {
    'greeting' => '挨拶',
    'purpose' => '用件',
    'wait' => '待ち',
    'absent' => '不在',
    'rejection' => '断り',
    'no_human' => '人へは回さない',
    'repeat' => '聞き直し',
    'closing' => '締め'
  }.freeze

  def self.current
    order(:id).first
  end

  def text_for(key)
    send("#{key}_text")
  rescue NoMethodError
    nil
  end
end
