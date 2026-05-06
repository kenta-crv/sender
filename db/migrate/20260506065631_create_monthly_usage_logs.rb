class CreateMonthlyUsageLogs < ActiveRecord::Migration[6.1]
  def change
    create_table :monthly_usage_logs do |t|
      t.references :client, null: false, foreign_key: true
      t.string :month, null: false
      t.integer :sent_count, null: false, default: 0

      t.timestamps
    end

    add_index :monthly_usage_logs, [:client_id, :month], unique: true
  end
end