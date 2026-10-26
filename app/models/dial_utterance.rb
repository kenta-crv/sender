class DialUtterance < ApplicationRecord
  belongs_to :dial_script

  validates :phrase, presence: true
  validates :script_key, presence: true, inclusion: { in: DialScript::INTENT_KEYS }

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
