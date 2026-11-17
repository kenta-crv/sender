class InboundReply < ApplicationRecord
  CLASSIFICATIONS = {
    'human' => '人の返信',
    'unknown' => '不明',
    'auto' => '自動受付',
    'other' => 'メルマガ・迷惑'
  }.freeze
  INTENTS = { 'interest' => '興味', 'question' => '質問', 'decline' => '断り', 'none' => 'その他' }.freeze

  belongs_to :sent_message, optional: true
  belongs_to :customer, optional: true

  # 手動で直した分類があればそちらを優先する
  def final_classification
    manual_classification.presence || classification
  end

  def intent_label
    INTENTS[intent]
  end

  scope :with_final, ->(c) {
    where(manual_classification: c).or(where(manual_classification: [nil, ''], classification: c))
  }
end
