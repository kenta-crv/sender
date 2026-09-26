class AddDialScriptToCalls < ActiveRecord::Migration[6.1]
  def change
    add_column :call_batches, :dial_script_id, :integer
    add_index :call_batches, :dial_script_id
    add_column :calls, :dial_script_id, :integer
    add_index :calls, :dial_script_id

    change_column_default :twilio_configs, :no_answer_timeout, from: 7, to: 10
    reversible do |dir|
      dir.up { execute "UPDATE twilio_configs SET no_answer_timeout = 10" }
    end
  end
end
