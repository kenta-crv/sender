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

        unless client.stripe_customer_id.present?
          Rails.logger.error "[TrialProcessor] stripe_customer_id missing client_id=#{client.id}"
          next
        end

        idempotency_key = "trial_upgrade_#{subscription.id}"

        stripe_price_id = ENV["STRIPE_PRICE_STANDARD"]

        unless stripe_price_id.present?
          Rails.logger.error "[TrialProcessor] STRIPE_PRICE_STANDARD missing"
          next
        end

        stripe_subscription = Stripe::Subscription.create(
          {
            customer: client.stripe_customer_id,
            items: [
              {
                price: stripe_price_id
              }
            ],
            metadata: {
              client_id: client.id,
              upgraded_from_trial: true
            }
          },
          {
            idempotency_key: idempotency_key
          }
        )

        unless stripe_subscription.present?
          Rails.logger.error "[TrialProcessor] subscription create failed subscription_id=#{subscription.id}"
          next
        end

        subscription.expire_trial_and_upgrade!

        latest_subscription = client.subscriptions
                                    .where(status: :active)
                                    .order(created_at: :desc)
                                    .first

        if latest_subscription.present?
          latest_subscription.update!(
            stripe_subscription_id: stripe_subscription.id
          )
        end

        Rails.logger.info "[TrialProcessor] success subscription_id=#{subscription.id}"

      rescue Stripe::StripeError => e
        Rails.logger.error "[TrialProcessor] stripe error subscription_id=#{subscription.id} #{e.class}: #{e.message}"

      rescue => e
        Rails.logger.error "[TrialProcessor] error subscription_id=#{subscription.id} #{e.class}: #{e.message}"
      end
    end
  end
end