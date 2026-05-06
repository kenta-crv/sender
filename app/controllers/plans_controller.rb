class PlansController < ApplicationController
  before_action :authenticate_client!

  def index
    @is_new_account = current_client.created_at > Subscription::TRIAL_DAYS.days.ago

    # =========================
    # 現在のサブスク（必ず実データ）
    # =========================
    @subscription = current_client.subscriptions
                                 .where(status: :active)
                                 .order(created_at: :desc)
                                 .first

    # fallback（念のため）
    if @subscription.nil?
      @subscription = current_client.subscriptions
                                   .order(created_at: :desc)
                                   .first
    end

    # =========================
    # 支払い履歴
    # =========================
    @payments = current_client.payments
                              .order(created_at: :desc)
                              .limit(50)
  end

  def select
    plan_type = params[:plan_type]

    unless Subscription::PLAN_PRICES.key?(plan_type.to_sym)
      redirect_to plans_path, alert: "無効なプランです。"
      return
    end

    # =========================
    # TRIAL
    # =========================
    if plan_type == "trial" && current_client.created_at > Subscription::TRIAL_DAYS.days.ago

      current_client.subscriptions.where(status: :active).update_all(status: :cancelled)

      trial_end = Subscription::TRIAL_DAYS.days.from_now

      subscription = current_client.subscriptions.create!(
        plan_type: :trial,
        status: :active,
        trial_ends_at: trial_end
      )

      current_client.update!(
        subscription_plan: "trial",
        subscription_status: "active",
        trial_ends_at: trial_end
      )

      redirect_to plans_path, notice: "無料トライアルを開始しました。"
      return
    end

    redirect_to checkout_confirmation_path(plan_type: plan_type)
  end
end