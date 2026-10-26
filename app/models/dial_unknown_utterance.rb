class DialUnknownUtterance < ApplicationRecord
  belongs_to :dial_script, optional: true
  belongs_to :call, optional: true

  validates :transcript, presence: true
end
