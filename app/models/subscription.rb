class Subscription < ApplicationRecord
  belongs_to :client

  enum plan_type: { trial: "trial", standard: "standard", enterprise: "enterprise" }
  enum status: { active: "active", cancelled: "cancelled", expired: "expired" }

  validates :plan_type, presence: true
  validates :status, presence: true

  # =========================
  # 表示名（追加）
  # =========================
  PLAN_NAMES = {
    trial: "トライアルプラン",
    standard: "スタンダードプラン",
    enterprise: "エンタープライズプラン"
  }.freeze

  # =========================
  # 価格
  # =========================
  PLAN_PRICES = {
    trial: 0,
    standard: 49_800,
    enterprise: 98_000
  }.freeze

  DELIVERY_COST = 50

  # =========================
  # 上限
  # =========================
  PLAN_DELIVERY_LIMITS = {
    trial: 1000,
    standard: 15_000,
    enterprise: 40_000
  }.freeze

  TRIAL_DAYS = 10

  # =========================
  # helper（追加）
  # =========================
  def plan_name
    PLAN_NAMES[plan_type.to_sym]
  end

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

  def trial_expired?
    trial? && trial_ends_at.present? && trial_ends_at <= Time.current
  end

  # =========================
  # トライアル期限 → 自動移行
  # =========================
  def expire_trial_and_upgrade!
    return unless trial?
    return if trial_ends_at.blank?
    return if trial_ends_at > Time.current
    return if status != "active"

    transaction do
      update!(status: :expired)

      client.subscriptions.where(status: :active).update_all(status: :cancelled)

      client.subscriptions.create!(
        plan_type: :standard,
        status: :active
      )

      client.update!(
        subscription_plan: "standard",
        subscription_status: "active"
      )
    end
  end
end