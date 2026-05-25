class ClickTrackingLink < ApplicationRecord
  belongs_to :customer
  belongs_to :client, optional: true
  belongs_to :admin, optional: true

  has_many :click_logs, dependent: :destroy

  before_validation :generate_token, on: :create

  validates :token, presence: true, uniqueness: true

  private

  def generate_token
    self.token ||= SecureRandom.hex(24)
  end
end