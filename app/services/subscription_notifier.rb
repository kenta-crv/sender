# frozen_string_literal: true

class SubscriptionNotifier
  ADMIN_EMAIL = "info@j-work.jp"
  CACHE_TTL = 10.minutes

  class << self
    def registered(subscription)
      notify(:registered, subscription)
    end

    def changed(subscription, previous_plan:)
      notify(:changed, subscription, previous_plan: previous_plan)
    end

    def cancelled(subscription)
      notify(:cancelled, subscription)
    end

    private

    def notify(event, subscription, previous_plan: nil)
      return if subscription.client.blank?

      dedup_key = "subscription_notify:#{subscription.id}:#{event}:#{subscription.plan_type}:#{subscription.status}"
      return if Rails.cache.exist?(dedup_key)

      Rails.cache.write(dedup_key, true, expires_in: CACHE_TTL)

      args = {
        event: event,
        subscription: subscription,
        previous_plan: previous_plan
      }

      SubscriptionMailer.notification(**args).deliver_now
      if subscription.client.email.present?
        SubscriptionMailer.client_notification(**args).deliver_now
      end
    rescue => e
      Rails.logger.error "[SubscriptionNotifier] #{event} failed subscription_id=#{subscription.id} #{e.message}"
    end
  end
end
