class AddStreamFields < ActiveRecord::Migration[6.1]
  def change
    add_column :twilio_configs, :stream_mode_enabled, :boolean, default: false
    add_column :calls, :stream_sid, :string
    add_column :calls, :speech_detected_at, :datetime
  end
end
