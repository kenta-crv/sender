require "test_helper"

class ClickTrackingControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  BROWSER_UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36"

  setup do
    @customer = Customer.create!(company: "Stay Click Co")
    @tracking = ClickTrackingLink.create!(
      customer: @customer,
      target_url: "https://drafity.pro"
    )
  end

  test "redirect does not record a click" do
    get click_tracking_path(@tracking.token), headers: { "User-Agent" => BROWSER_UA }

    assert_response :redirect
    assert_equal 0, @tracking.reload.clicked_count
    assert_equal 0, @tracking.click_logs.count
  end

  test "stay records a click after visible landing" do
    post ftkn_stay_path, params: { token: @tracking.token }, headers: { "User-Agent" => BROWSER_UA }

    assert_response :ok
    assert_equal 1, @tracking.reload.clicked_count
    assert_equal 1, @tracking.click_logs.count
  end

  test "stay ignores bot user agents" do
    post ftkn_stay_path,
         params: { token: @tracking.token },
         headers: { "User-Agent" => "Slackbot-LinkExpanding 1.0 (+https://api.slack.com/robots)" }

    assert_response :ok
    assert_equal 0, @tracking.reload.clicked_count
  end

  test "stay does not double-count the same ip within the dedup window" do
    2.times do
      post ftkn_stay_path, params: { token: @tracking.token }, headers: { "User-Agent" => BROWSER_UA }
    end

    assert_equal 1, @tracking.reload.clicked_count
  end

  test "click history page notes the 3 second stay rule" do
    admin = Admin.create!(
      email: "stay-#{SecureRandom.hex(4)}@example.com",
      password: "password",
      password_confirmation: "password"
    )
    sign_in admin
    submission = Submission.create!(headline: "Drafity stay", url: "https://drafity.pro")

    get click_history_submission_path(submission)

    assert_response :success
    assert_includes @response.body, "ページ表示後に3秒以上滞在"
  end
end
