class Client::SubscriptionsController < ApplicationController
  before_action :authenticate_client!
  before_action :set_subscription, only: [:show, :update, :cancel, :cancel_confirm]

  def show
    @subscription = current_client.current_subscription
    @payments = current_client.payments.order(created_at: :desc).limit(10)
  end

  def update
    new_plan_type = params[:plan_type]

    unless Subscription::PLAN_PRICES.key?(new_plan_type.to_sym)
      redirect_to client_subscription_path, alert: "無効なプランです。"
      return
    end

    if new_plan_type != current_client.subscription_plan
      redirect_to checkout_confirmation_path(plan_type: new_plan_type)
    else
      redirect_to client_subscription_path, notice: "同じプランです。"
    end
  end

  def cancel_confirm
    unless @subscription&.active?
      redirect_to client_subscription_path,
                  alert: "現在有効なサブスクリプションはありません。"
    end
  end

  def cancel
    unless @subscription.present?
      redirect_to client_subscription_path,
                  alert: "サブスクリプションが存在しません。"
      return
    end

    begin
      if @subscription.stripe_subscription_id.present?
        stripe_subscription = Stripe::Subscription.retrieve(
          @subscription.stripe_subscription_id
        )

        stripe_subscription.cancel
      end

      if @subscription.update(status: :cancelled)
        current_client.update(
          subscription_status: "cancelled",
          subscription_plan: "none"
        )

        redirect_to client_subscription_path,
                    notice: "サブスクリプションをキャンセルしました。機能が制限されます。"
      else
        redirect_to client_subscription_path,
                    alert: "キャンセル処理に失敗しました。"
      end

    rescue Stripe::StripeError => e
      Rails.logger.error "Stripe cancel error: #{e.class} - #{e.message}"

      redirect_to client_subscription_path,
                  alert: "Stripe側のキャンセル処理に失敗しました。"
    end
  end

  private

  def set_subscription
    @subscription = current_client.current_subscription
  end
end