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

    # Stripe Checkoutではカード保存状態を事前判定しない
    @has_saved_card = current_client.stripe_customer_id.present?

    if @campaign_id.present?
      @campaign = current_client.campaigns.find(@campaign_id)

      recipient_count = current_client.push_subscriptions
                                      .where(status: "active")
                                      .count

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

    Rails.logger.info "Checkout create - plan_type: #{plan_type}, campaign_id: #{campaign_id}"

    begin
      if campaign_id.present?
        process_delivery_payment(campaign_id)

      elsif plan_type.present?
        process_subscription_payment(plan_type)

      else
        redirect_to plans_path,
                    alert: "プランまたはキャンペーンを選択してください。"
      end

    rescue Stripe::CardError => e
      Rails.logger.error "Stripe Card Error: #{e.class} - #{e.message}"

      redirect_to checkout_confirmation_path(
        plan_type: plan_type,
        campaign_id: campaign_id
      ),
                  alert: "カード決済に失敗しました: #{e.message}"

    rescue Stripe::StripeError => e
      Rails.logger.error "Stripe API Error: #{e.class} - #{e.message}"

      redirect_to checkout_confirmation_path(
        plan_type: plan_type,
        campaign_id: campaign_id
      ),
                  alert: "決済処理に失敗しました: #{e.message}"

    rescue => e
      Rails.logger.error "Payment error: #{e.class} - #{e.message}"

      redirect_to checkout_confirmation_path(
        plan_type: plan_type,
        campaign_id: campaign_id
      ),
                  alert: "決済処理中にエラーが発生しました: #{e.message}"
    end
  end

  def success
    @payment = Payment.find_by(id: params[:payment_id]) if params[:payment_id]
    @subscription = Subscription.find_by(id: params[:subscription_id]) if params[:subscription_id]
  end

  def cancel
    redirect_to client_dashboard_index_path,
                notice: "決済がキャンセルされました。"
  end

  private

  def process_delivery_payment(campaign_id)
    campaign = current_client.campaigns.find(campaign_id)

    recipient_count = current_client.push_subscriptions
                                    .where(status: "active")
                                    .count

    amount = skip_delivery_payment? ? 0 : recipient_count * Subscription::DELIVERY_COST

    if amount.zero?
      payment = current_client.payments.create!(
        campaign: campaign,
        amount: amount,
        status: 'succeeded',
        description: "Campaign delivery payment for #{recipient_count} recipients"
      )

      begin
        result = send_campaign(campaign)

        redirect_to checkout_success_path(payment_id: payment.id),
                    notice: "決済が完了し、キャンペーンを送信しました。（成功: #{result[:sent]}件、失敗: #{result[:failed]}件）"

      rescue => e
        Rails.logger.error "Campaign send failed after payment (campaign_id=#{campaign.id}): #{e.class} - #{e.message}"

        redirect_to checkout_success_path(payment_id: payment.id),
                    alert: "決済は完了しましたが、キャンペーン送信に失敗しました: #{e.message}"
      end

      return
    end

    session = Stripe::Checkout::Session.create(
      payment_method_types: ['card'],
      mode: 'payment',

      customer_email: current_client.email,

      line_items: [
        {
          price_data: {
            currency: 'jpy',
            product_data: {
              name: "Campaign delivery: #{campaign.title}"
            },
            unit_amount: amount
          },
          quantity: 1
        }
      ],

      metadata: {
        client_id: current_client.id,
        campaign_id: campaign.id,
        payment_type: 'campaign'
      },

      success_url: checkout_success_url,
      cancel_url: checkout_cancel_url
    )

    redirect_to session.url, allow_other_host: true
  end

  def process_subscription_payment(plan_type)
    unless plan_type.present? && Subscription::PLAN_PRICES.key?(plan_type.to_sym)
      redirect_to plans_path, alert: "無効なプランです。"
      return
    end

    # =========================
    # TRIAL
    # =========================
    if plan_type == 'trial'
      current_client.subscriptions
                    .where(status: :active)
                    .update_all(status: :cancelled)

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
    # Stripe Price ID
    # =========================
    stripe_price_id =
      case plan_type
      when 'light'
        ENV.fetch('STRIPE_PRICE_LIGHT')
      when 'standard'
        ENV.fetch('STRIPE_PRICE_STANDARD')
      when 'premium'
        ENV.fetch('STRIPE_PRICE_PREMIUM')
      else
        nil
      end

    unless stripe_price_id.present?
      redirect_to plans_path,
                  alert: "Stripe Price ID が設定されていません。"
      return
    end

    session = Stripe::Checkout::Session.create(
      payment_method_types: ['card'],
      mode: 'subscription',

      customer_email: current_client.email,

      line_items: [
        {
          price: stripe_price_id,
          quantity: 1
        }
      ],

      metadata: {
        client_id: current_client.id,
        plan_type: plan_type,
        payment_type: 'subscription'
      },

      success_url: checkout_success_url,
      cancel_url: checkout_cancel_url
    )

    redirect_to session.url, allow_other_host: true
  end

  def send_campaign(campaign)
    ::PushNotificationSender.deliver(campaign)
  end

  def skip_delivery_payment?
    Rails.env.development? || ENV["SKIP_DELIVERY_PAYMENT"] == "true"
  end
end