class CreateFormDetectionBatches < ActiveRecord::Migration[6.1]
  def change
    create_table :form_detection_batches do |t|
      t.integer :total_count
      t.integer :processed_count
      t.integer :success_count
      t.integer :error_count
      t.integer :client_id
      t.string :status
      t.datetime :started_at
      t.datetime :completed_at
      t.text :customer_ids

      t.timestamps
    end
  end
end
