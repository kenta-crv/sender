class TwilioConfig < ApplicationRecord
  def self.current
    first || create!(
      from_number: ENV['TWILIO_FROM_NUMBER'] || '',
      operator_number: ENV['OPERATOR_NUMBER'] || ''
    )
  end

  # 環境変数をフォールバックとして利用
  def from_number
    val = super
    val.present? ? val : ENV['TWILIO_FROM_NUMBER']
  end

  def operator_number
    val = super
    val.present? ? val : ENV['OPERATOR_NUMBER']
  end
end
