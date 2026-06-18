class AddSerpAndFormDetectionLimitsToMonthlyUsageLogs < ActiveRecord::Migration[6.1]
  def change
    add_column :monthly_usage_logs, :serp_api_limit, :integer, default: 0, null: false
    add_column :monthly_usage_logs, :serp_api_used, :integer, default: 0, null: false
    add_column :monthly_usage_logs, :form_detection_limit, :integer, default: 0, null: false
    add_column :monthly_usage_logs, :form_detection_used, :integer, default: 0, null: false
  end
end
