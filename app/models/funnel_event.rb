class FunnelEvent < ApplicationRecord
  PAGES = %w[top registration checkout_confirmation stripe_session_expired].freeze
  EVENT_TYPES = %w[visit abandon proceed].freeze

  belongs_to :click_tracking_link, optional: true

  validates :page,       presence: true, inclusion: { in: PAGES }
  validates :event_type, presence: true, inclusion: { in: EVENT_TYPES }

  scope :by_page,       ->(p) { where(page: p) }
  scope :by_event_type, ->(t) { where(event_type: t) }
  scope :recent,        -> { order(created_at: :desc) }
  scope :this_month,    -> { where(created_at: Time.current.beginning_of_month..Time.current.end_of_month) }

  def self.funnel_summary(since: 30.days.ago)
    where(created_at: since..)
      .group(:page, :event_type)
      .count
  end
end
