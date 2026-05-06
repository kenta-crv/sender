class Subscription::TrialProcessor
  def self.run
    Subscription
      .where(plan_type: :trial, status: :active)
      .where("trial_ends_at IS NOT NULL")
      .where("trial_ends_at <= ?", Time.current)
      .find_each do |subscription|

      client = subscription.client

      begin
        next if subscription.status == "expired"

        idempotency_key = "trial_upgrade_#{subscription.id}"

        charge = Payjp::Charge.create(
          {
            amount: Subscription::PLAN_PRICES[:standard],
            currency: "jpy",
            customer: client.payjp_customer_id,
            description: "Auto upgrade from trial"
          },
          {
            idempotency_key: idempotency_key
          }
        )

        unless charge.paid
          Rails.logger.error "[TrialProcessor] charge failed subscription_id=#{subscription.id}"
          next
        end

        subscription.expire_trial_and_upgrade!

        Rails.logger.info "[TrialProcessor] success subscription_id=#{subscription.id}"

      rescue => e
        Rails.logger.error "[TrialProcessor] error subscription_id=#{subscription.id} #{e.class}: #{e.message}"
      end
    end
  end
end