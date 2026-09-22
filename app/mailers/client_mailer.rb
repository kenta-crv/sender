class ClientMailer < ApplicationMailer
  default from: 'info@j-work.jp'

  def registration_email(client)
    @client = client
    mail(to: @client.email, subject: '【Okurite】会員登録完了のお知らせ')
  end

  def plan_registration_email(client, subscription, payment)
    @client = client
    @subscription = subscription
    @payment = payment
    mail(to: @client.email, subject: "【Okurite】プラン登録完了のお知らせ")
  end

  def serp_run_stopped(run)
    @run = run
    recipients = serp_stop_recipients(run)
    return if recipients.empty?

    pending = run.targets.where(result_status: "pending").count
    body = [
      "SERP補完が途中で停止しました。",
      "",
      "業種: #{run.industry.presence || '全業種'}",
      "対象: #{run.target_count}件",
      "未処理のまま残った件数: #{pending}件",
      "理由: #{run.error_message.presence || '不明'}",
      "",
      "続きは画面から改めて開始してください。自動では再開しません。"
    ].join("\n")

    mail(
      to: recipients,
      from: "info@j-work.jp",
      subject: "【Okurite】SERP補完が停止しました"
    ) do |format|
      format.text { render plain: body }
    end
  end

  private

  def serp_stop_recipients(run)
    addresses = [SubscriptionNotifier::ADMIN_EMAIL]
    client = Client.find_by(id: run.client_id)
    addresses << client.email if client&.email.present?
    addresses.map { |address| address.to_s.strip }.reject(&:blank?).uniq
  end
end
