class Client < ApplicationRecord
  class DuplicateCardError < StandardError; end

  CORPORATE_TITLE_PATTERN = /(株式会社|有限会社|合同会社|合資会社|合名会社)/.freeze
  TEL_DIGITS_ONLY_PATTERN = /\A[0-9]+\z/.freeze

  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :monthly_usage_logs, dependent: :destroy

  has_many :subscriptions, dependent: :destroy
  has_one :active_subscription, -> { where(status: :active) }, class_name: "Subscription"
  has_many :payments, dependent: :destroy

  has_many :customers
  has_many :form_submission_batches
  has_many :submissions
  has_many :delivery_opt_outs, dependent: :destroy

  validates :company, presence: { message: "を入力してください" }, on: :create, if: :registration_ip_present?
  validate :company_must_include_corporate_title, on: :create, if: :registration_ip_present?
  validates :tel, presence: { message: "を入力してください" }, on: :create, if: :registration_ip_present?
  validate :tel_must_be_digits_only, on: :create, if: :registration_ip_present?

  def full_name
    [first_name, last_name].compact.join(" ")
  end

  def client?
    true
  end

  def current_subscription
    active_subscription || subscriptions.order(created_at: :desc).first
  end

  def on_trial?
    subscription_plan == "trial" && trial_ends_at.present? && trial_ends_at > Time.current
  end

  def subscription_active?
    subscription_status == "active"
  end

  def monthly_sent_count
    monthly_usage_log.sent_count
  end

  def monthly_limit
    return 0 unless subscription_active?
    current_subscription&.delivery_limit || 0
  end

  def can_send_this_month?(count)
    (monthly_sent_count + count) <= monthly_limit
  end

  def increment_monthly_sent!(count)
    monthly_usage_log.increment!(:sent_count, count)
  end

  # トライアル終了時の自動アップグレードロジック（Stripe・エンタープライズプラン仕様に修正）
  def check_and_upgrade_expired_trial
    return unless subscription_plan == "trial"
    return unless trial_ends_at.present?
    return if trial_ends_at > Time.current

    unless stripe_customer_id.present?
      Rails.logger.error "Client #{id} trial expired but no Stripe customer ID found"
      return nil
    end

    begin
      amount = Subscription::PLAN_PRICES[:enterprise] # 98,000円

      # Stripeでの決済実行
      charge = Stripe::Charge.create(
        amount: amount,
        currency: "jpy",
        customer: stripe_customer_id,
        description: "Enterprise Plan subscription (trial upgrade)"
      )

      if charge.status == "succeeded"
        subscriptions.where(status: :active).update_all(status: :cancelled)

        subscription = subscriptions.create!(
          plan_type: :enterprise,
          status: :active,
          stripe_subscription_id: charge.id, # 決済IDを保持
          trial_ends_at: nil
        )

        update!(
          subscription_plan: "enterprise",
          subscription_status: "active",
          trial_ends_at: nil
        )

        payments.create!(
          amount: amount,
          stripe_payment_intent_id: charge.id,
          status: "succeeded",
          description: "Enterprise Plan subscription (trial upgrade)"
        )

        Rails.logger.info "Client #{id} trial expired, charged 98,000 JPY via Stripe and upgraded to enterprise plan"
        subscription
      else
        Rails.logger.error "Client #{id} trial expired but Stripe charge failed: #{charge.failure_message}"

        subscriptions.where(status: :active).update_all(status: :cancelled)

        update!(
          subscription_plan: "enterprise",
          subscription_status: "active",
          trial_ends_at: nil
        )

        nil
      end
    rescue => e
      Rails.logger.error "Error upgrading trial via Stripe for client #{id}: #{e.message}"
      nil
    end
  end

  after_create :initialize_trial_subscription, if: :new_record?
  before_create :generate_api_key_if_blank

  private

  def generate_api_key_if_blank
    self.api_key = SecureRandom.hex(32) if api_key.blank?
  end

  def registration_ip_present?
    registration_ip.present?
  end

  def company_must_include_corporate_title
    return if company.blank?
    return if company.match?(CORPORATE_TITLE_PATTERN)

    errors.add(:company, "は法人敬称（株式会社、有限会社、合同会社など）を含めてください")
  end

  def tel_must_be_digits_only
    return if tel.blank?
    return if tel.match?(TEL_DIGITS_ONLY_PATTERN)

    errors.add(:tel, "は数字のみで入力してください")
  end

  def initialize_trial_subscription
    subscriptions.create!(
      plan_type: :trial,
      status: :active,
      trial_ends_at: Subscription::TRIAL_DAYS.days.from_now
    )

    update(
      subscription_plan: "trial",
      subscription_status: "active",
      trial_ends_at: Subscription::TRIAL_DAYS.days.from_now
    )
  end

  def current_month_key
    Time.current.strftime("%Y-%m")
  end

  public

  def payment_method_registered?
    return false unless stripe_customer_id.present?

    return true if stripe_payment_method_id.present?

    subscriptions.where(status: :active).where.not(stripe_subscription_id: [nil, ""]).exists?
  end

  def ensure_stripe_customer!
    return stripe_customer_id if stripe_customer_id.present?

    customer = Stripe::Customer.create(
      email: email,
      metadata: { client_id: id }
    )
    update!(stripe_customer_id: customer.id)
    customer.id
  end

  def assign_payment_method!(payment_method_id)
    ensure_stripe_customer!

    payment_method = Stripe::PaymentMethod.retrieve(payment_method_id)
    fingerprint = payment_method.card&.fingerprint

    if fingerprint.present? && Client.where.not(id: id).exists?(card_fingerprint: fingerprint)
      Stripe::PaymentMethod.detach(payment_method_id)
      raise DuplicateCardError, "このクレジットカードは既に登録されています。"
    end

    Stripe::PaymentMethod.attach(
      payment_method_id,
      { customer: stripe_customer_id }
    )

    Stripe::Customer.update(
      stripe_customer_id,
      invoice_settings: { default_payment_method: payment_method_id }
    )

    update!(
      stripe_payment_method_id: payment_method_id,
      card_fingerprint: fingerprint
    )

    create_stripe_trial_subscription_if_needed!
    true
  end

  def create_stripe_trial_subscription_if_needed!
    return unless subscription_plan == "trial"
    return unless trial_ends_at.present? && trial_ends_at > Time.current
    return if subscriptions.where.not(stripe_subscription_id: [nil, ""]).exists?

    stripe_price_id = ENV["STRIPE_PRICE_ENTERPRISE"]
    return unless stripe_price_id.present?

    remaining_days = ((trial_ends_at - Time.current) / 1.day).ceil
    return if remaining_days <= 0

    stripe_subscription = Stripe::Subscription.create(
      customer: stripe_customer_id,
      items: [{ price: stripe_price_id }],
      trial_period_days: remaining_days,
      metadata: {
        client_id: id,
        upgraded_from_trial: true
      }
    )

    subscriptions.where(status: :active).where(stripe_subscription_id: [nil, ""]).find_each do |sub|
      sub.update!(stripe_subscription_id: stripe_subscription.id)
    end
  end

  def usage_limits
    plan_usage_limits || { serp_api_limit: 0, form_detection_limit: 0 }
  end

  def monthly_usage_log
    log = MonthlyUsageLog.find_or_create_by!(
      client_id: id,
      month: current_month_key
    )

    limits = plan_usage_limits
    if limits && (log.serp_api_limit != limits[:serp_api_limit] || log.form_detection_limit != limits[:form_detection_limit])
      log.update(limits)
    end

    log
  end

  def plan_usage_limits
    subscription = current_subscription
    if subscription
      return {
        serp_api_limit: subscription.serp_api_limit,
        form_detection_limit: subscription.form_detection_limit
      }
    end

    plan = subscription_plan.presence&.to_sym
    return nil unless plan && Subscription::PLAN_SERP_API_LIMITS.key?(plan)

    {
      serp_api_limit: Subscription::PLAN_SERP_API_LIMITS[plan],
      form_detection_limit: Subscription::PLAN_FORM_DETECTION_LIMITS[plan]
    }
  end
end