class RemoveCampaignIdFromPayments < ActiveRecord::Migration[6.1]
  def up
    remove_column :payments, :campaign_id if column_exists?(:payments, :campaign_id)
  end

  def down
    add_column :payments, :campaign_id, :integer
  end
end
