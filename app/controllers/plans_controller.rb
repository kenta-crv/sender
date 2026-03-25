class PlansController < ApplicationController
  before_action :authenticate_client!

  def index
    @is_new_account = current_client.created_at > 15.days.ago
    @current_subscription = current_client.current_subscription
  end

  def select
    plan_type = params[:plan_type]
    
    unless Subscription::PLAN_PRICES.key?(plan_type.to_sym)
      redirect_to plans_path, alert: "無効なプランです。"
      return
    end

    if plan_type == "trial" && current_client.created_at > 15.days.ago
      current_client.subscriptions.create!(
        plan_type: :trial,
        status: :active,
        trial_ends_at: 15.days.from_now
      )
      current_client.update!(
        subscription_plan: "trial",
        subscription_status: "active",
        trial_ends_at: 15.days.from_now
      )
      redirect_to client_dashboard_index_path, notice: "無料トライアルを開始しました。"
    else
      redirect_to checkout_confirmation_path(plan_type: plan_type)
    end
  end
end

