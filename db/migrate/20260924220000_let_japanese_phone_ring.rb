class LetJapanesePhoneRing < ActiveRecord::Migration[6.1]
  def up
    change_column_default :twilio_configs, :no_answer_timeout, from: 10, to: 30
    execute "UPDATE twilio_configs SET no_answer_timeout = 30"
  end

  def down
    change_column_default :twilio_configs, :no_answer_timeout, from: 30, to: 10
    execute "UPDATE twilio_configs SET no_answer_timeout = 10"
  end
end
