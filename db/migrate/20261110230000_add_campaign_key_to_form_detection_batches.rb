class AddCampaignKeyToFormDetectionBatches < ActiveRecord::Migration[6.1]
  def change
    add_column :form_detection_batches, :campaign_key, :string
    add_index :form_detection_batches, :campaign_key
  end
end
