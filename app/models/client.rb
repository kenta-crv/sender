class Client < ApplicationRecord
  # Devise modules
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
  has_many :monthly_usage_logs, dependent: :destroy
  # Associations
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
  # validates :api_key, uniqueness: true

  # Methods
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

  def check_and_upgrade_expired_trial
    return unless subscription_plan == "trial"
    return unless trial_ends_at.present?
    return if trial_ends_at > Time.current

    unless payjp_customer_id.present?
      Rails.logger.error "Client #{id} trial expired but no PayJP customer ID found"
      return nil
    end

    begin
      amount = Subscription::PLAN_PRICES[:standard]
      
      charge = Payjp::Charge.create(
        amount: amount,
        currency: 'jpy',
        customer: payjp_customer_id,
        description: "Standard Plan subscription (trial upgrade)"
      )

      if charge.paid
        subscriptions.where(status: :active).update_all(status: :cancelled)
        
        subscription = subscriptions.create!(
          plan_type: :standard,
          status: :active,
          payjp_subscription_id: charge.id,
          trial_ends_at: nil
        )

        update!(
          subscription_plan: "standard",
          subscription_status: "active",
          trial_ends_at: nil
        )

        payments.create!(
          campaign_id: nil,
          amount: amount,
          payjp_charge_id: charge.id,
          status: charge.paid ? 'succeeded' : 'failed',
          description: "Standard Plan subscription (trial upgrade)"
        )

        Rails.logger.info "Client #{id} trial expired, charged and upgraded to standard plan"
        subscription
      else
        Rails.logger.error "Client #{id} trial expired but charge failed: #{charge.failure_message}"
        subscriptions.where(status: :active).update_all(status: :cancelled)
        update!(
          subscription_plan: "standard",
          subscription_status: "active",
          trial_ends_at: nil
        )
        nil
      end
    rescue => e
      Rails.logger.error "Error upgrading trial for client #{id}: #{e.message}"
      nil
    end
  end

  after_create :initialize_trial_subscription, if: :new_record?
  before_create :generate_api_key_if_blank

  private

  def generate_api_key_if_blank
    if api_key.blank?
      self.api_key = SecureRandom.hex(32)
    end
  end

  def initialize_trial_subscription
    subscriptions.create!(
      plan_type: :trial,
      status: :active,
      trial_ends_at: 15.days.from_now
    )
    update(
      subscription_plan: "trial",
      subscription_status: "active",
      trial_ends_at: 15.days.from_now
    )
  end

    # =========================
  # 月キー
  # =========================
  def current_month_key
    Time.current.strftime("%Y-%m")
  end

  # =========================
  # 月次ログ取得 or 作成
  # =========================
  def monthly_usage_log
    MonthlyUsageLog.find_or_create_by!(
      client_id: id,
      month: current_month_key
    )
  end

  # =========================
  # 今月の送信数
  # =========================
  def monthly_sent_count
    monthly_usage_log.sent_count
  end

  # =========================
  # 今月の上限（Subscription準拠）
  # =========================
  def monthly_limit
    current_subscription&.delivery_limit || 0
  end

  # =========================
  # 送信可能判定
  # =========================
  def can_send_this_month?(count)
    (monthly_sent_count + count) <= monthly_limit
  end

  # =========================
  # 加算処理
  # =========================
  def increment_monthly_sent!(count)
    monthly_usage_log.increment!(:sent_count, count)
  end
end
