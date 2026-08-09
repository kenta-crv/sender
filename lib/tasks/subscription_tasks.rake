namespace :subscription do
  desc "Expire trial subscriptions without auto-charging"
  task expire_trials: :environment do
    Subscription::TrialProcessor.run
  end
end
