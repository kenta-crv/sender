class AddClickTrackingLinkToFunnelEvents < ActiveRecord::Migration[6.1]
  def change
    add_column :funnel_events, :click_tracking_link_id, :integer
    add_index  :funnel_events, :click_tracking_link_id
  end
end
