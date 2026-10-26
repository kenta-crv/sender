class DialFaq < ApplicationRecord
  belongs_to :dial_script

  validates :question, presence: true
  validates :answer, presence: true

  def phrase_list
    raw = phrases.presence || '[]'
    parsed = JSON.parse(raw)
    Array(parsed).map(&:to_s).map(&:strip).reject(&:blank?)
  rescue JSON::ParserError
    phrases.to_s.split(/[\n,]/).map(&:strip).reject(&:blank?)
  end

  def embedding_vector
    return nil if embedding.blank?

    JSON.parse(embedding)
  rescue JSON::ParserError
    nil
  end

  def embedding_vector=(arr)
    self.embedding = arr.nil? ? nil : JSON.generate(arr)
  end
end
