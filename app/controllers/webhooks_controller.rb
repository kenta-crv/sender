class WebhooksController < ApplicationController
  skip_before_action :verify_authenticity_token

  def stripe
    payload = request.body.read
    sig_header = request.env['HTTP_STRIPE_SIGNATURE']
    endpoint_secret = ENV['STRIPE_WEBHOOK_SECRET']
    event = nil

    begin
      event = Stripe::Webhook.construct_event(payload, sig_header, endpoint_secret)
    rescue JSON::ParserError, Stripe::SignatureVerificationError
      head :bad_request
      return
    end

    Rails.logger.info "EVENT_TYPE=#{event.type}"

    case event.type
    when 'checkout.session.completed'
      handle_checkout_session_completed(event.data.object)

    when 'customer.subscription.deleted'
      handle_subscription_deleted(event.data.object)

    # Stripe新形式・インボイス決済成功対応
    when 'invoice.payment_succeeded', 'invoice_payment.paid', 'invoice.paid'
      handle_invoice_payment_succeeded(event.data.object)

    when 'invoice.finalized'
      Rails.logger.info "invoice finalized received"
    end

    head :ok
  end

  private

  def handle_checkout_session_completed(session)
    client_id = session.metadata["client_id"]
    return if client_id.blank?

    client = Client.find_by(id: client_id)
    return if client.blank?

    begin
      if session.mode == 'subscription'
        plan_type = session.metadata.plan_type
        trial_ends_at = nil 

        if defined?(Subscription) && Subscription.respond_to?(:plan_types)
          unless Subscription.plan_types.keys.include?(plan_type.to_s)
            Rails.logger.error "================ INVALID PLAN TYPE ================"
            Rails.logger.error "Client ID: #{client.id} - Received plan_type '#{plan_type}' is NOT defined."
            Rails.logger.error "==================================================="
            return
          end
        end

        Subscription.transaction do
          sub = client.subscriptions.find_or_initialize_by(stripe_subscription_id: session.subscription)
          
          client.subscriptions.where.not(id: sub.id).update_all(status: :cancelled)

          final_plan_type = (plan_type == "trial") ? "enterprise" : plan_type
          
          sub.update!(
            plan_type: final_plan_type,
            status: :active,
            trial_ends_at: trial_ends_at
          )
            
          client.update!(
            subscription_plan: final_plan_type,
            subscription_status: 'active'
          )
        end # <- Subscription.transaction の end が不足していたのを修正

      elsif session.mode == 'payment'
        campaign_id = session.metadata.campaign_id
        campaign = client.campaigns.find_by(id: campaign_id) if campaign_id.present?

        client.payments.create!(
          campaign: campaign,
          amount: session.amount_total,
          status: 'succeeded',
          stripe_payment_intent_id: session.payment_intent,
          description: campaign ? "Campaign delivery: #{campaign.title}" : "One-time payment"
        )

        ::PushNotificationSender.deliver(campaign) if campaign
      end

    rescue => e
      Rails.logger.error "================ WEBHOOK ERROR (CHECKOUT COMPLETED) ================"
      Rails.logger.error e.class
      Rails.logger.error e.message
      Rails.logger.error e.backtrace.first(5).join("\n")
      Rails.logger.error "===================================================================="
    end
  end

  def handle_subscription_deleted(stripe_subscription)
    sub = Subscription.find_by(stripe_subscription_id: stripe_subscription.id)
    return if sub.blank?

    sub.update!(status: :cancelled)
    sub.client.update!(subscription_status: 'cancelled', subscription_plan: 'none')
  end

  def handle_invoice_payment_succeeded(invoice)
    Rails.logger.info "================ INVOICE START ================"
    Rails.logger.info invoice.inspect

    # 1. 決済用インテントIDをStripeオブジェクトとHash療法の構造から確実に抽出
    payment_intent_id = nil
    if invoice.respond_to?(:payment_intent) && invoice.payment_intent.present?
      payment_intent_id = invoice.payment_intent
    elsif invoice.respond_to?(:payment) && invoice.payment.present? && invoice.payment.respond_to?(:payment_intent)
      payment_intent_id = invoice.payment.payment_intent
    end
    
    # ハッシュ形式でのフォールバック
    if payment_intent_id.blank? && invoice.respond_to?(:dig)
      payment_intent_id = invoice.dig(:payment_intent) || invoice.dig(:payment, :payment_intent) || invoice.dig("payment", "payment_intent")
    end
    payment_intent_id ||= (invoice.respond_to?(:id) ? invoice.id : nil)

    return if payment_intent_id.blank?

    # すでに登録済みなら早期終了
    if Payment.exists?(stripe_payment_intent_id: payment_intent_id)
      Rails.logger.info "Payment already exists for #{payment_intent_id}. Skipping."
      return
    end

    # 2. 【大改修】サブスクリプションIDの確実なドットメソッド/ハッシュ両対応抽出
    stripe_subscription_id = nil
    
    if invoice.respond_to?(:subscription) && invoice.subscription.present?
      stripe_subscription_id = invoice.subscription
    elsif invoice.respond_to?(:parent) && invoice.parent.present?
      # ログに現れていた parent -> subscription_details -> subscription メソッドチェーンを完全解析
      if invoice.parent.respond_to?(:subscription_details) && invoice.parent.subscription_details.present?
        if invoice.parent.subscription_details.respond_to?(:subscription)
          stripe_subscription_id = invoice.parent.subscription_details.subscription
        end
      end
    end

    # オブジェクトではなく生Hashで届いた場合のディープ・フォールバック
    if stripe_subscription_id.blank? && invoice.respond_to?(:dig)
      stripe_subscription_id = invoice.dig(:subscription) || 
                               invoice.dig(:parent, :subscription_details, :subscription) ||
                               invoice.dig("parent", "subscription_details", "subscription")
    end

    # 3. 契約データの特定
    sub = nil
    if stripe_subscription_id.present?
      sub = Subscription.find_by(stripe_subscription_id: stripe_subscription_id)
    end

    # StripeのAPIから直接インボイスを再取得してサブスクIDを引っ張る最終バックアップ
    if sub.blank? && invoice.respond_to?(:invoice) && invoice.invoice.present?
      begin
        stripe_invoice = Stripe::Invoice.retrieve(invoice.invoice)
        if stripe_invoice&.subscription.present?
          stripe_subscription_id = stripe_invoice.subscription
          sub = Subscription.find_by(stripe_subscription_id: stripe_subscription_id)
        end
      rescue => e
        Rails.logger.error "Failed to retrieve invoice from Stripe API: #{e.message}"
      end
    end

    # 金額の抽出
    amount_paid = 0
    if invoice.respond_to?(:amount_paid)
      amount_paid = invoice.amount_paid.to_i
    elsif invoice.respond_to?(:dig)
      amount_paid = (invoice.dig(:amount_paid) || invoice.dig("amount_paid") || 0).to_i
    end

    return if amount_paid <= 0

    # サブスクリプションが見つからない場合はスキップしてcheckout.session側に委ねる
    if sub.blank? || sub.client.blank?
      Rails.logger.info "Subscription or Client not found in DB yet (Sub ID: #{stripe_subscription_id}). Skipping safely for next retry or session completed."
      return
    end

    begin
      plan_name = sub.plan_type.to_s.capitalize

      payment = sub.client.payments.create!(
        amount: amount_paid,
        status: 'succeeded',
        stripe_payment_intent_id: payment_intent_id,
        description: "#{plan_name} Plan Payment"
      )

      Rails.logger.info "=== PAYMENT SUCCESSFULLY CREATED IN DB: #{payment.id} ==="

    rescue => e
      Rails.logger.error "================ WEBHOOK ERROR (INVOICE) ================"
      Rails.logger.error e.class
      Rails.logger.error e.message
      Rails.logger.error e.backtrace.first(10).join("\n")
      Rails.logger.error "========================================================="
      raise e
    end
  end
end