class AddClientIdToFormSubmissionBatches < ActiveRecord::Migration[6.1]
  def change
    add_reference :form_submission_batches, :client, null: true, foreign_key: true
  end
end
