class AddCampaignKeyToPipelineRecords < ActiveRecord::Migration[6.1]
  def change
    add_column :job_postings, :campaign_key, :string
    add_index :job_postings, :campaign_key
    add_column :form_submission_batches, :campaign_key, :string
    add_index :form_submission_batches, :campaign_key
  end
end
