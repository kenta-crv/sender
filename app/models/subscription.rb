class Subscription < ApplicationRecord
end
class Subscription < ApplicationRecord
  belongs_to :client

  enum plan_type: { trial: "trial", standard: "standard", enterprise: "enterprise" }
  enum status: { active: "active", cancelled: "cancelled", expired: "expired" }

  validates :plan_type, presence: true
  validates :status, presence: true

  PLAN_PRICES = {
    trial: 0,
    standard: 98_000,
    enterprise: 198_000
  }.freeze

  DELIVERY_COST = 50

  PLAN_DELIVERY_LIMITS = {
    trial: 2,
    standard: 50,
    enterprise: Float::INFINITY
  }.freeze

  def price
    PLAN_PRICES[plan_type.to_sym] || 0
  end

  def delivery_limit
    PLAN_DELIVERY_LIMITS[plan_type.to_sym] || 0
  end

  def unlimited?
    delivery_limit == Float::INFINITY
  end

  def can_send_delivery?(count)
    return true if unlimited?
    count <= delivery_limit
  end

  def trial?
    plan_type == "trial"
  end

  def trial_active?
    trial? && trial_ends_at.present? && trial_ends_at > Time.current
  end
end

