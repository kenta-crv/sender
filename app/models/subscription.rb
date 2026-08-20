class Subscription < ApplicationRecord
  belongs_to :client

  enum plan_type: { trial: "trial", standard: "standard", enterprise: "enterprise" }
  enum status: { active: "active", cancelled: "cancelled", expired: "expired" }

  validates :plan_type, presence: true
  validates :status, presence: true

  validates :stripe_subscription_id,
            uniqueness: true,
            allow_nil: true

  after_commit :notify_registered, on: :create
  after_commit :notify_updated, on: :update

  PLAN_NAMES = {
    trial: "トライアル",
    standard: "スタンダードプラン",
    enterprise: "エンタープライズプラン"
  }.freeze

  PLAN_PRICES = {
    trial: 0,
    standard: 49_800,
    enterprise: 98_000
  }.freeze

  PLAN_DELIVERY_LIMITS = {
    trial: 50,
    standard: 15_000,
    enterprise: 40_000
  }.freeze

  PLAN_SERP_API_LIMITS = {
    trial: 7,
    standard: 1000,
    enterprise: 3000
  }.freeze

  PLAN_FORM_DETECTION_LIMITS = {
    trial: 15,
    standard: 15_000,
    enterprise: 40_000
  }.freeze

  TRIAL_DAYS = 14
  STANDARD_INTRO_PERCENT_OFF = 15
  STANDARD_INTRO_MONTHS = 3

  def self.intro_coupon_id_for(plan_type)
    return ENV["STRIPE_COUPON_STANDARD_INTRO"].presence if plan_type.to_s == "standard"

    nil
  end

  def self.standard_intro_price
    (PLAN_PRICES[:standard] * (100 - STANDARD_INTRO_PERCENT_OFF) / 100.0).round
  end

  def plan_name
    PLAN_NAMES[plan_type.to_sym]
  end

  def price
    PLAN_PRICES[plan_type.to_sym] || 0
  end

  def delivery_limit
    PLAN_DELIVERY_LIMITS[plan_type.to_sym] || 0
  end

  def serp_api_limit
    PLAN_SERP_API_LIMITS[plan_type.to_sym] || 0
  end

  def form_detection_limit
    PLAN_FORM_DETECTION_LIMITS[plan_type.to_sym] || 0
  end

  def unlimited?
    delivery_limit == Float::INFINITY
  end

  # 今月これまでに送信した累積件数を含めて、上限を超えないか検証
  def can_send_delivery?(count)
    return true if unlimited?
    (client.monthly_sent_count + count) <= delivery_limit
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

  # 自動課金せず期限切れにする（継続はスタンダード等を Checkout で契約）
  def expire_trial_without_charge!
    return unless trial?
    return if trial_ends_at.blank?
    return if trial_ends_at > Time.current
    return if status != "active"

    update!(status: :expired)
    client.update_columns(subscription_status: "expired") if client.has_attribute?(:subscription_status)
  end

  def expire_trial_and_upgrade!
    expire_trial_without_charge!
  end

  private

  def notify_registered
    SubscriptionNotifier.registered(self)
  end

  def notify_updated
    if saved_change_to_status? && cancelled?
      SubscriptionNotifier.cancelled(self)
    elsif saved_change_to_plan_type?
      SubscriptionNotifier.changed(self, previous_plan: plan_type_before_last_save)
    end
  end
end