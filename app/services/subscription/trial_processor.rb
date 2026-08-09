class Subscription::TrialProcessor
  def self.run
    Subscription
      .where(plan_type: :trial, status: :active)
      .where("trial_ends_at IS NOT NULL")
      .where("trial_ends_at <= ?", Time.current)
      .find_each do |subscription|
      begin
        subscription.expire_trial_without_charge!
        Rails.logger.info "[TrialProcessor] expired without charge subscription_id=#{subscription.id}"
      rescue => e
        Rails.logger.error "[TrialProcessor] error subscription_id=#{subscription.id} #{e.class}: #{e.message}"
      end
    end
  end
end
