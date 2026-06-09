class Client < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  has_many :monthly_usage_logs, dependent: :destroy

  has_one :plan
  has_many :push_subscriptions, dependent: :destroy
  has_many :campaigns, dependent: :destroy
  has_many :campaign_results, through: :campaigns
  has_one :install_script, dependent: :destroy
  has_many :subscriptions, dependent: :destroy
  has_one :active_subscription, -> { where(status: :active) }, class_name: "Subscription"
  has_many :payments, dependent: :destroy

  has_many :customers
  has_many :form_submission_batches
  has_many :submissions

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

  def can_send_campaign?(recipient_count)
    return false unless subscription_active?
    sub = current_subscription
    return false unless sub
    sub.can_send_delivery?(recipient_count)
  end

  def monthly_sent_count
    monthly_usage_log.sent_count
  end

  def monthly_limit
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
          campaign_id: nil,
          amount: amount,
          stripe_charge_id: charge.id, # Stripeの決済IDに変更して記録
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

  def monthly_usage_log
    MonthlyUsageLog.find_or_create_by!(
      client_id: id,
      month: current_month_key
    )
  end
end