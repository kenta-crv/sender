require 'test_helper'

class ClientMonthlyUsageLogTest < ActiveSupport::TestCase
  test 'monthly_usage_log syncs limits from subscription plan' do
    client = Client.create!(
      email: "usage-#{SecureRandom.hex(6)}@example.com",
      password: 'password',
      password_confirmation: 'password',
      subscription_plan: 'trial',
      subscription_status: 'active'
    )
    client.subscriptions.create!(plan_type: :trial, status: :active)

    log = client.monthly_usage_log

    assert_equal Subscription::PLAN_SERP_API_LIMITS[:trial], log.serp_api_limit
    assert_equal Subscription::PLAN_FORM_DETECTION_LIMITS[:trial], log.form_detection_limit
    assert_equal Subscription::PLAN_SERP_API_LIMITS[:trial], client.usage_limits[:serp_api_limit]
  end
end
