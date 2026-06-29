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

end
