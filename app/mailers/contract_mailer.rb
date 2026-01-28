class ContractMailer < ActionMailer::Base
  default from: "info@okey.work"
  def received_email(contract)
    @contract = contract
    mail from: contract.email
    mail to: "info@okey.work"
    mail(subject: '株式会社セールスプロにお問い合わせがありました') do |format|
      format.text
    end
  end

  def send_email(contract)
    @contract = contract
    mail to: contract.email
    mail(subject: 'お問い合わせ頂きありがとうございます。') do |format|
      format.text
    end
  end
end
