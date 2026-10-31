class AddSapSendFlags < ActiveRecord::Migration[6.1]
  def change
    add_column :form_submission_batches, :ignore_forbidden_text, :boolean, default: false, null: false
    add_column :form_detection_batches, :sap_pipeline, :boolean, default: false, null: false
    add_column :job_postings, :classified_at, :datetime
  end
end
