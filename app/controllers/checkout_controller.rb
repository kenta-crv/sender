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
      recipient_count = current_client.push_subscriptions.where(status: "active").count
      @amount = skip_delivery_payment? ? 0 : recipient_count * Subscription::DELIVERY_COST
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
      
      if @plan_type == 'trial'
        @description = "無料トライアル (15日間)"
        @amount = 0
        unless current_client.created_at > 15.days.ago
          redirect_to plans_path, alert: "無料トライアルは新規アカウントのみ利用できます。"
          return
        end
      else
        @description = "#{@plan_type.capitalize} Plan"
      end
    end

    @subscription = Subscription.new(plan_type: @plan_type) if @plan_type.present?
    @payjp_public_key = Rails.application.credentials.dig(:payjp, :public_key) || ENV['PAYJP_PUBLIC_KEY']
  end

  def create
    plan_type = params[:plan_type]
    campaign_id = params[:campaign_id]
    payjp_token = params[:payjp_token]

    Rails.logger.info "Checkout create - plan_type: #{plan_type}, campaign_id: #{campaign_id}, token present: #{payjp_token.present?}"

    unless payjp_token.present?
      redirect_to checkout_confirmation_path(plan_type: plan_type, campaign_id: campaign_id), 
                  alert: "カード情報が正しく入力されていません。"
      return
    end

    begin
      if campaign_id.present?
        process_delivery_payment(campaign_id, payjp_token)
      elsif plan_type.present?
        process_subscription_payment(plan_type, payjp_token)
      else
        redirect_to plans_path, alert: "プランまたはキャンペーンを選択してください。"
      end
    rescue Payjp::CardError => e
      Rails.logger.error "Pay.jp Card Error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      redirect_to checkout_confirmation_path(plan_type: plan_type, campaign_id: campaign_id),
                  alert: "カード決済に失敗しました: #{e.message}"
    rescue Payjp::PayjpError => e
      Rails.logger.error "Pay.jp API Error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      redirect_to checkout_confirmation_path(plan_type: plan_type, campaign_id: campaign_id),
                  alert: "決済処理に失敗しました: #{e.message}"
    rescue => e
      Rails.logger.error "Payment error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      redirect_to checkout_confirmation_path(plan_type: plan_type, campaign_id: campaign_id),
                  alert: "決済処理中にエラーが発生しました: #{e.message}"
    end
  end

  def success
    @payment = Payment.find_by(id: params[:payment_id]) if params[:payment_id]
    @subscription = Subscription.find_by(id: params[:subscription_id]) if params[:subscription_id]
  end

  def cancel
    redirect_to client_dashboard_index_path, notice: "決済がキャンセルされました。"
  end

  private

  def process_delivery_payment(campaign_id, payjp_token)
    campaign = current_client.campaigns.find(campaign_id)
    recipient_count = current_client.push_subscriptions.where(status: "active").count
    amount = skip_delivery_payment? ? 0 : recipient_count * Subscription::DELIVERY_COST

    charge =
      if amount.zero?
        OpenStruct.new(id: "dev-skip-charge", paid: true)
      else
        Payjp::Charge.create(
          amount: amount,
          currency: 'jpy',
          card: payjp_token,
          description: "Campaign delivery: #{campaign.title}"
        )
      end

    payment = current_client.payments.create!(
      campaign: campaign,
      amount: amount,
      payjp_charge_id: charge.id,
      status: charge.paid ? 'succeeded' : 'failed',
      description: "Campaign delivery payment for #{recipient_count} recipients"
    )

    if payment.succeeded?
      begin
        result = send_campaign(campaign)
        redirect_to checkout_success_path(payment_id: payment.id),
                    notice: "決済が完了し、キャンペーンを送信しました。（成功: #{result[:sent]}件、失敗: #{result[:failed]}件）"
      rescue => e
        Rails.logger.error "Campaign send failed after payment (campaign_id=#{campaign.id}): #{e.class} - #{e.message}"
        redirect_to checkout_success_path(payment_id: payment.id),
                    alert: "決済は完了しましたが、キャンペーン送信に失敗しました: #{e.message}"
      end
    else
      redirect_to checkout_confirmation_path(campaign_id: campaign_id),
                  alert: "決済に失敗しました。"
    end
  end

def process_subscription_payment(plan_type, payjp_token)
  unless plan_type.present? && Subscription::PLAN_PRICES.key?(plan_type.to_sym)
    redirect_to plans_path, alert: "無効なプランです。"
    return
  end

  amount = Subscription::PLAN_PRICES[plan_type.to_sym]

  customer_id = current_client.payjp_customer_id

  unless customer_id
    customer = Payjp::Customer.create(
      email: current_client.email,
      description: "User #{current_client.id}",
      card: payjp_token
    )
    customer_id = customer.id
    current_client.update!(payjp_customer_id: customer_id)
  else
    customer = Payjp::Customer.retrieve(customer_id)
    customer.cards.create(card: payjp_token)
  end

  # =========================
  # TRIAL
  # =========================
  if plan_type == 'trial'
    current_client.subscriptions.where(status: :active).update_all(status: :cancelled)

    subscription = current_client.subscriptions.create!(
      plan_type: :trial,
      status: :active,
      trial_ends_at: Subscription::TRIAL_DAYS.days.from_now
    )

    current_client.update!(
      subscription_plan: "trial",
      subscription_status: "active",
      trial_ends_at: subscription.trial_ends_at
    )

    redirect_to checkout_success_path(subscription_id: subscription.id),
                notice: "トライアルを開始しました。"
    return
  end

  # =========================
  # PAID PLAN
  # =========================
  charge = Payjp::Charge.create(
    amount: amount,
    currency: 'jpy',
    customer: customer_id,
    description: "#{plan_type} Plan"
  )

  if charge.paid
    current_client.subscriptions.where(status: :active).update_all(status: :cancelled)

    subscription = current_client.subscriptions.create!(
      plan_type: plan_type,
      status: :active,
      payjp_subscription_id: charge.id
    )

    current_client.update!(subscription_plan: plan_type)

    redirect_to checkout_success_path(subscription_id: subscription.id),
                notice: "プラン登録完了"
  else
    redirect_to checkout_confirmation_path(plan_type: plan_type),
                alert: "決済失敗"
  end
end

  def send_campaign(campaign)
    ::PushNotificationSender.deliver(campaign)
  end

  def skip_delivery_payment?
    Rails.env.development? || ENV["SKIP_DELIVERY_PAYMENT"] == "true"
  end
end