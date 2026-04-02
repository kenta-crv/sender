class CreateCallBatches < ActiveRecord::Migration[6.1]
  def change
    create_table :call_batches do |t|
      t.string :name
      t.integer :total_count, default: 0
      t.integer :processed_count, default: 0
      t.integer :success_count, default: 0
      t.integer :failure_count, default: 0
      t.integer :transferred_count, default: 0
      t.string :status, default: "pending"
      t.text :customer_ids
      t.text :error_log, default: "[]"
      t.integer :concurrent_lines, default: 3
      t.datetime :started_at
      t.datetime :completed_at
      t.integer :worker_id

      t.timestamps
    end

    add_index :call_batches, :status
    add_index :call_batches, :worker_id
  end
end
