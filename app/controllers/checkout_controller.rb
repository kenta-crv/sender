class CheckoutController < ApplicationController
  before_action :authenticate_client!

  def confirmation
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'

    @plan_type = params[:plan_type]
    @campaign_id = params[:campaign_id]

    if @plan_type.blank? && @campaign_id.blank?
      redirect_to plans_path, alert: "プランを選択してください。"
      return
    end

    if @campaign_id.present?
      @campaign = current_client.campaigns.find(@campaign_id)

      recipient_count = current_client.push_subscriptions
                                      .where(status: "active")
                                      .count

      @amount =
        skip_delivery_payment? ? 0 :
        recipient_count * Subscription::DELIVERY_COST

      @description = "Campaign delivery: #{@campaign.title}"

      unless current_client.can_send_campaign?(recipient_count)
        redirect_to client_campaigns_path(current_client),
                    alert: "配信数の上限に達しています。プランをアップグレードしてください。"
        return
      end

    else
      unless Subscription::PLAN_PRICES.key?(@plan_type.to_sym)
        redirect_to plans_path, alert: "無効なプランです。"
        return
      end

      @amount = Subscription::PLAN_PRICES[@plan_type.to_sym]

      if @plan_type == "trial"
        @description = "無料トライアル (#{Subscription::TRIAL_DAYS}日間)"
        @amount = 0

        if current_client.created_at < Subscription::TRIAL_DAYS.days.ago || current_client.subscriptions.exists?(plan_type: :trial)
          redirect_to plans_path,
                      alert: "無料トライアルは新規アカウントのみ利用できます。"
          return
        end
      else
        @description = "#{@plan_type.capitalize} Plan"
      end
    end

    @subscription = Subscription.new(plan_type: @plan_type) if @plan_type.present?
  end

  def create
    plan_type = params[:plan_type]
    campaign_id = params[:campaign_id]

    Rails.logger.info(
      "[Checkout#create] plan_type=#{plan_type} campaign_id=#{campaign_id}"
    )

    if plan_type == "trial"
      if current_client.created_at < Subscription::TRIAL_DAYS.days.ago || current_client.subscriptions.exists?(plan_type: :trial)
        redirect_to plans_path, alert: "無料トライアルは新規アカウントのみ利用できます。"
        return
      end
    end

    begin
      if campaign_id.present?
        process_delivery_payment(campaign_id)
      elsif plan_type.present?
        process_subscription_payment(plan_type)
      else
        redirect_to plans_path, alert: "プランまたはキャンペーンを選択してください。"
      end

    rescue Stripe::CardError => e
      Rails.logger.error("[Stripe Card Error] #{e.class} #{e.message}")
      redirect_to checkout_confirmation_path(plan_type: plan_type, campaign_id: campaign_id), alert: "カード決済に失敗しました: #{e.message}"
    rescue Stripe::StripeError => e
      Rails.logger.error("[Stripe API Error] #{e.class} #{e.message}")
      redirect_to checkout_confirmation_path(plan_type: plan_type, campaign_id: campaign_id), alert: "Stripe決済エラー: #{e.message}"
    rescue => e
      Rails.logger.error("[Checkout Error] #{e.class} #{e.message}")
      redirect_to checkout_confirmation_path(plan_type: plan_type, campaign_id: campaign_id), alert: "決済処理中にエラーが発生しました。"
    end
  end

  def success
    session_id = params[:session_id]

    if session_id.blank?
      @subscription = current_client.subscriptions.order(created_at: :desc).first
      @payment = current_client.payments.order(created_at: :desc).first
      @amount = @payment&.amount || 0
      @invoice_id = @payment&.stripe_payment_intent_id
      @plan_name = @subscription&.plan_name || "プラン"
      return
    end

    begin
      @session = Stripe::Checkout::Session.retrieve(session_id)

      @amount = @session.amount_total
      @invoice_id = @session.invoice || @session.payment_intent

      @plan_type = @session.metadata["plan_type"]
      @payment_type = @session.metadata["payment_type"]

      if @payment_type == "subscription" && @plan_type.present?
        @plan_name = Subscription::PLAN_NAMES[@plan_type.to_sym] rescue @plan_type.to_s.capitalize
      else
        @plan_name = "都度配信決済"
      end

      if @session.payment_status == "paid" || @session.payment_status == "no_payment_required"
        if @payment_type == "subscription" && @plan_type.present? && @session.subscription.present?

          Subscription.transaction do
            sub = current_client.subscriptions.find_or_initialize_by(stripe_subscription_id: @session.subscription)
            current_client.subscriptions.where.not(id: sub.id).update_all(status: :cancelled)

            sub.update!(plan_type: @plan_type, status: :active)
            current_client.update!(
              subscription_plan: @plan_type,
              subscription_status: "active"
            )
          end

          @subscription = current_client.subscriptions.find_by(stripe_subscription_id: @session.subscription)

          @payment = current_client.payments.find_by(stripe_payment_intent_id: @invoice_id) || current_client.payments.order(created_at: :desc).first
          if @subscription
            ClientMailer.plan_registration_email(current_client, @subscription, @payment).deliver_now
          end

        elsif @payment_type == "campaign"
          campaign_id = @session.metadata["campaign_id"]
          if campaign_id.present?
            campaign = current_client.campaigns.find_by(id: campaign_id)

            payment_intent_id = @session.payment_intent || @session.id
            unless current_client.payments.exists?(stripe_payment_intent_id: payment_intent_id)
              current_client.payments.create!(
                campaign: campaign,
                amount: @amount,
                status: 'succeeded',
                stripe_payment_intent_id: payment_intent_id,
                description: "Campaign delivery: #{campaign&.title}"
              )
              ::PushNotificationSender.deliver(campaign) if campaign
            end
          end
        end
      end

      @payment = current_client.payments.find_by(stripe_payment_intent_id: @invoice_id) || current_client.payments.order(created_at: :desc).first

    rescue Stripe::StripeError => e
      Rails.logger.error("[Stripe Success Retrieve Error] #{e.message}")
      @plan_name = "プラン"
      @amount = 0
      @invoice_id = "N/A"
    end
  end

  def cancel
    redirect_to plans_path, alert: "決済がキャンセルされました。"
  end

  private

  def process_delivery_payment(campaign_id)
    campaign = current_client.campaigns.find(campaign_id)

    recipient_count = current_client.push_subscriptions.where(status: "active").count

    amount = skip_delivery_payment? ? 0 : recipient_count * Subscription::DELIVERY_COST

    if amount.zero?
      current_client.payments.create!(
        campaign: campaign,
        amount: 0,
        status: "succeeded",
        stripe_payment_intent_id: "dev_skip",
        description: "Campaign delivery payment"
      )

      result = send_campaign(campaign)
      redirect_to checkout_success_path, notice: "送信完了（成功: #{result[:sent]}件 / 失敗: #{result[:failed]}件）"
      return
    end

    session = Stripe::Checkout::Session.create(
      mode: "payment",
      customer_email: current_client.email,
      payment_method_types: ["card"],
      line_items: [
        {
          quantity: 1,
          price_data: {
            currency: "jpy",
            unit_amount: amount,
            product_data: { name: "Campaign delivery: #{campaign.title}" }
          }
        }
      ],
      metadata: {
        client_id: current_client.id,
        campaign_id: campaign.id,
        payment_type: "campaign"
      },
      success_url: "#{checkout_success_url}?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: checkout_cancel_url
    )

    redirect_to session.url, allow_other_host: true
  end

  def process_subscription_payment(plan_type)
    unless Subscription::PLAN_PRICES.key?(plan_type.to_sym)
      redirect_to plans_path, alert: "無効なプランです。"
      return
    end

    stripe_price_id = case plan_type
                      when "standard"
                        ENV["STRIPE_PRICE_STANDARD"]
                      when "trial", "enterprise"
                        ENV["STRIPE_PRICE_ENTERPRISE"]
                      else
                        nil
                      end

    unless stripe_price_id.present?
      redirect_to plans_path, alert: "Stripe Price ID が未設定です。"
      return
    end

    customer_id = current_client.stripe_customer_id
    customer = if customer_id.present?
                 Stripe::Customer.retrieve(customer_id)
               else
                 new_cust = Stripe::Customer.create(email: current_client.email, metadata: { client_id: current_client.id })
                 current_client.update!(stripe_customer_id: new_cust.id)
                 new_cust
               end

    session_params = {
      mode: "subscription",
      customer: customer.id,
      payment_method_types: ["card"],
      line_items: [{ price: stripe_price_id, quantity: 1 }],
      metadata: {
        client_id: current_client.id,
        plan_type: plan_type.to_s,
        payment_type: "subscription"
      },
      success_url: "#{checkout_success_url}?session_id={CHECKOUT_SESSION_ID}",
      cancel_url: checkout_cancel_url
    }

    if plan_type == "trial"
      session_params[:subscription_data] = { trial_period_days: Subscription::TRIAL_DAYS }
    end

    session = Stripe::Checkout::Session.create(session_params)
    redirect_to session.url, allow_other_host: true
  end

  def send_campaign(campaign)
    ::PushNotificationSender.deliver(campaign)
  end

  def skip_delivery_payment?
    Rails.env.development? || ENV["SKIP_DELIVERY_PAYMENT"] == "true"
  end
end