namespace :subscription do
  desc "Expire trial subscriptions and upgrade them"
  task expire_trials: :environment do
    Subscription::TrialExpirer.call
  end
end