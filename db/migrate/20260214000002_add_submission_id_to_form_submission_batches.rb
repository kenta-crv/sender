class AddSubmissionIdToFormSubmissionBatches < ActiveRecord::Migration[6.1]
  def change
    add_column :form_submission_batches, :submission_id, :integer
  end
end
