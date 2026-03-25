class Client::SubscriptionsController < ApplicationController
  before_action :authenticate_client!
  before_action :set_subscription, only: [:show, :update, :cancel]

  def show
    @subscription = current_client.current_subscription
    @payments = current_client.payments.order(created_at: :desc).limit(10)
  end

  def update
    new_plan_type = params[:plan_type]
    
    unless Subscription::PLAN_PRICES.key?(new_plan_type.to_sym)
      redirect_to client_subscription_path(current_client), alert: "無効なプランです。"
      return
    end

    if new_plan_type != current_client.subscription_plan
      redirect_to checkout_confirmation_path(plan_type: new_plan_type)
    else
      redirect_to client_subscription_path(current_client), notice: "同じプランです。"
    end
  end

  def cancel
    @subscription = current_client.current_subscription
    
    if @subscription&.update(status: :cancelled)
      current_client.update(subscription_status: "cancelled")
      redirect_to client_subscription_path, notice: "サブスクリプションをキャンセルしました。"
    else
      redirect_to client_subscription_path, alert: "キャンセルに失敗しました。"
    end
  end

  private

  def set_subscription
    @subscription = current_client.current_subscription
  end
end

