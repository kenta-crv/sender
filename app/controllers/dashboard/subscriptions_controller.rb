module Dashboard
  class SubscriptionsController < ApplicationController
    before_action :authenticate_any!
    before_action :set_target_client
    before_action :set_subscription, only: [:show, :update, :cancel, :cancel_confirm]

    def show
      @subscription = @target_client.subscriptions.order(created_at: :desc).first
      @payments = @target_client.payments.order(created_at: :desc).limit(10)
    end

    def update
      new_plan_type = params[:plan_type]

      unless Subscription::PLAN_PRICES.key?(new_plan_type.to_sym)
        redirect_to dashboard_subscription_path(client_id: params[:client_id]), alert: "無効なプランです。"
        return
      end

      if new_plan_type != @target_client.subscription_plan
        redirect_to checkout_confirmation_path(plan_type: new_plan_type, client_id: params[:client_id])
      else
        redirect_to dashboard_subscription_path(client_id: params[:client_id]), notice: "同じプランです。"
      end
    end

    def cancel_confirm
      unless @subscription&.status == 'active'
        redirect_to dashboard_subscription_path(client_id: params[:client_id]), alert: "現在有効なサブスクリプションはありません。"
        return
      end

      begin
        stripe_subscription = Stripe::Subscription.retrieve(@subscription.stripe_subscription_id)
        
        # Stripe::Subscriptionの直下、またはitemsの最初の要素からcurrent_period_endを取得
        period_end = stripe_subscription.respond_to?(:current_period_end) ? stripe_subscription.current_period_end : nil
        period_end ||= stripe_subscription.items&.data&.first&.current_period_end

        if period_end
          @available_until = Time.at(period_end).to_date
        else
          @available_until = Date.today.end_of_month
        end
      rescue Stripe::StripeError => e
        Rails.logger.error "Stripe retrieve error: #{e.message}"
        @available_until = Date.today.end_of_month
      end
    end

    def cancel
      unless @subscription&.status == 'active'
        redirect_to dashboard_subscription_path(client_id: params[:client_id]),
                    alert: "サブスクリプションが存在しません。"
        return
      end

      begin
        if @subscription.stripe_subscription_id.present?
          # Stripe SDKの最新仕様に合わせ、cancelメソッドの引数として更新
          Stripe::Subscription.update(
            @subscription.stripe_subscription_id,
            { cancel_at_period_end: true }
          )
        end

        if @subscription.update(status: :cancelled)
          @target_client.update(
            subscription_status: "cancelled",
            subscription_plan: "none"
          )

          redirect_to dashboard_subscription_path(client_id: params[:client_id]),
                      notice: "解約手続きが完了しました。有料機能は期間終了日まで継続してご利用いただけます。"
        else
          redirect_to dashboard_subscription_path(client_id: params[:client_id]),
                      alert: "解約処理に失敗しました。"
        end

      rescue Stripe::StripeError => e
        Rails.logger.error "Stripe cancel error: #{e.class} - #{e.message}"

        redirect_to dashboard_subscription_path(client_id: params[:client_id]),
                    alert: "Stripe側のキャンセル処理に失敗しました。"
      end
    end

    private

    def authenticate_any!
      unless admin_signed_in? || client_signed_in?
        redirect_to root_path, alert: "権限がありません。"
      end
    end

    def set_target_client
      if admin_signed_in?
        if params[:client_id].present?
          @target_client = Client.find(params[:client_id])
        else
          redirect_to root_path, alert: "クライアントを指定してください。"
        end
      else
        @target_client = current_client
      end
    end

    def set_subscription
      @subscription = @target_client.subscriptions.order(created_at: :desc).first
    end
  end
end