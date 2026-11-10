class KyujinboxBackfillJob < ApplicationJob
  def perform(campaign_key)
    campaign = Pipeline::Campaign.find(campaign_key)
    raise "キャンペーンが見つかりません: #{campaign_key}" if campaign.nil?

    Kyujinbox::Backfill.new(campaign: campaign).run
  end
end
