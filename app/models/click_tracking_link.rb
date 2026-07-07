class ClickTrackingLink < ApplicationRecord
  belongs_to :customer
  belongs_to :client, optional: true
  belongs_to :admin, optional: true
  belongs_to :submission, optional: true
  belongs_to :form_submission_batch, optional: true

  has_many :click_logs, dependent: :destroy

  before_validation :generate_token, on: :create

  validates :token, presence: true, uniqueness: true

  def batch_sent_at
    if form_submission_batch.present?
      form_submission_batch.started_at || form_submission_batch.created_at
    else
      created_at
    end
  end

  def batch_sent_at_estimated?
    form_submission_batch.blank?
  end

  private

  def generate_token
    self.token ||= SecureRandom.hex(24)
  end
end
