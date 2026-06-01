class ExtractTracking < ApplicationRecord
    def self.remaining_extractable_count
    today_total = where(created_at: Time.current.beginning_of_day..Time.current.end_of_day).sum(:total_count)
    daily_limit = ENV.fetch('EXTRACT_DAILY_LIMIT', '500').to_i
    [daily_limit - today_total, 0].max
  end
end
