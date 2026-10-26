class TwilioConfig < ApplicationRecord
  # 試験発信の相手役 / 転送先（固定）
  DEFAULT_TEST_TO_NUMBER = '+818020451020'.freeze      # 080-2045-1020
  DEFAULT_OPERATOR_NUMBER = '+81368204378'.freeze     # 03-6820-4378
  TEST_TO_DISPLAY = '08020451020'.freeze
  OPERATOR_DISPLAY = '03-6820-4378'.freeze

  def self.current
    first || create!(
      from_number: ENV['TWILIO_FROM_NUMBER'] || '',
      operator_number: default_operator_number
    )
  end

  def self.test_to_number
    ENV['TEST_TO_NUMBER'].presence || DEFAULT_TEST_TO_NUMBER
  end

  def self.default_operator_number
    ENV['OPERATOR_NUMBER'].presence || DEFAULT_OPERATOR_NUMBER
  end

  def self.apply_test_numbers!
    cfg = current
    cfg.update!(operator_number: default_operator_number)
    cfg
  end

  # 環境変数をフォールバックとして利用
  def from_number
    val = super
    val.present? ? val : ENV['TWILIO_FROM_NUMBER']
  end

  def operator_number
    val = super
    return val if val.present?

    self.class.default_operator_number
  end

  def stream_mode_enabled?
    stream_mode_enabled == true
  end
end
