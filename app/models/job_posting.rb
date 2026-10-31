class JobPosting < ApplicationRecord
  STATUSES = %w[new resolved skipped registered].freeze
  RECENT_SKIP_REASON = "30日以内に処理済み".freeze

  belongs_to :customer, optional: true

  validates :source, :job_key, :status, presence: true
  validates :job_key, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
end
