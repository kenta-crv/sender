class DialUtterance < ApplicationRecord
  belongs_to :dial_script

  validates :phrase, presence: true
  validates :script_key, presence: true, inclusion: { in: DialScript::SCRIPT_KEYS }
end
