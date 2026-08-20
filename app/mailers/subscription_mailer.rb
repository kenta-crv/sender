# frozen_string_literal: true

class SubscriptionMailer < ApplicationMailer
  PRODUCT = "Okurite"
  default from: "info@j-work.jp"

  def notification(event:, subscription:, previous_plan: nil)
    assign_common(event, subscription, previous_plan)

    mail(
      to: SubscriptionNotifier::ADMIN_EMAIL,
      subject: admin_subject
    )
  end

  def client_notification(event:, subscription:, previous_plan: nil)
    assign_common(event, subscription, previous_plan)

    mail(
      to: @client.email,
      subject: client_subject
    )
  end

  private

  def assign_common(event, subscription, previous_plan)
    @event = event.to_sym
    @subscription = subscription
    @client = subscription.client
    @previous_plan = previous_plan
    @previous_plan_name = plan_label(previous_plan)
    @client_name = [@client.try(:name), @client.try(:company)].find(&:present?) || "お客様"
    @dashboard_url = dashboard_index_url(**mailer_url_options)
  end

  def plan_label(plan_type)
    return "-" if plan_type.blank?

    Subscription::PLAN_NAMES[plan_type.to_sym] || plan_type.to_s
  end

  def mailer_url_options
    {
      host: ActionMailer::Base.default_url_options[:host].presence || "okurite.pro",
      protocol: ActionMailer::Base.default_url_options[:protocol].presence || "https"
    }
  end

  def admin_subject
    case @event
    when :registered
      @subscription.trial? ? "【#{PRODUCT}】トライアル申し込み" : "【#{PRODUCT}】サブスクリプション登録"
    when :changed
      "【#{PRODUCT}】サブスクリプション変更"
    when :cancelled
      "【#{PRODUCT}】サブスクリプション解約"
    else
      "【#{PRODUCT}】サブスクリプション通知"
    end
  end

  def client_subject
    case @event
    when :registered
      @subscription.trial? ? "【#{PRODUCT}】無料トライアル開始のお知らせ" : "【#{PRODUCT}】プラン登録完了のお知らせ"
    when :changed
      "【#{PRODUCT}】プラン変更完了のお知らせ"
    when :cancelled
      "【#{PRODUCT}】解約手続き完了のお知らせ"
    else
      "【#{PRODUCT}】ご契約に関するお知らせ"
    end
  end
end
