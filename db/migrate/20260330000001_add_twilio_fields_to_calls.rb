class AddTwilioFieldsToCalls < ActiveRecord::Migration[6.1]
  def change
    add_column :calls, :twilio_call_sid, :string
    add_column :calls, :flow_phase, :string
    add_column :calls, :speech_result, :text
    add_column :calls, :speech_category, :string
    add_column :calls, :speech_confidence, :float
    add_column :calls, :started_at, :datetime
    add_column :calls, :answered_at, :datetime
    add_column :calls, :ended_at, :datetime
    add_column :calls, :duration, :integer
    add_column :calls, :recording_url, :string
    add_column :calls, :recording_sid, :string
    add_column :calls, :transferred_to, :string
    add_column :calls, :conference_sid, :string
    add_column :calls, :twilio_status, :string
    add_column :calls, :call_batch_id, :integer

    add_index :calls, :twilio_call_sid
    add_index :calls, :call_batch_id
  end
end
