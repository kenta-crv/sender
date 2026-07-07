# frozen_string_literal: true

class SubscriptionMailer < ApplicationMailer
  default from: "info@j-work.jp", to: SubscriptionNotifier::ADMIN_EMAIL

  EVENT_SUBJECTS = {
    registered: "【Okurite】サブスクリプション登録",
    changed: "【Okurite】サブスクリプション変更",
    cancelled: "【Okurite】サブスクリプション解約"
  }.freeze

  def notification(event:, subscription:, previous_plan: nil)
    @event = event.to_sym
    @subscription = subscription
    @client = subscription.client
    @previous_plan = previous_plan

    mail(
      to: SubscriptionNotifier::ADMIN_EMAIL,
      subject: EVENT_SUBJECTS.fetch(@event, "【Okurite】サブスクリプション通知")
    )
  end
end
