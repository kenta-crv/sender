class AddSenderToFormSubmissionBatches < ActiveRecord::Migration[6.1]
  def change
    add_reference :form_submission_batches, :admin, foreign_key: true
  end
end