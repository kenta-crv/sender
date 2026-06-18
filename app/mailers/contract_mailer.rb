class ContractMailer < ActionMailer::Base
  default from: "info@j-work.jp"
  def received_email(contract)
    @contract = contract
    mail from: contract.email
    mail to: "info@j-work.jp"
    mail(subject: 'Okuriteにお問い合わせがありました') do |format|
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
