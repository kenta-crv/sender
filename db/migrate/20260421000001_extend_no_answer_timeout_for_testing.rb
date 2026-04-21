class ExtendNoAnswerTimeoutForTesting < ActiveRecord::Migration[6.1]
  def up
    execute "UPDATE twilio_configs SET no_answer_timeout = 30"
  end

  def down
    execute "UPDATE twilio_configs SET no_answer_timeout = 7"
  end
end
