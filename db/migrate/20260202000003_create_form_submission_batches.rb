class CreateFormSubmissionBatches < ActiveRecord::Migration[6.1]
  def change
    create_table :form_submission_batches do |t|
      t.integer :total_count, default: 0
      t.integer :processed_count, default: 0
      t.integer :success_count, default: 0
      t.integer :failure_count, default: 0
      t.string :status, default: 'pending'
      t.integer :current_customer_id
      t.text :customer_ids
      t.text :error_log
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end
  end
end
