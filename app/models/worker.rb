class Worker < ApplicationRecord
  devise :database_authenticatable, :registerable, 
         :recoverable, :rememberable, :validatable
  has_many :calls

  # 手動送信の実績集計
  def stats_summary
    {
      today:      build_stats(Time.zone.now.beginning_of_day..Time.zone.now.end_of_day),
      this_week:  build_stats(Time.zone.now.beginning_of_week..Time.zone.now.end_of_week),
      this_month: build_stats(Time.zone.now.beginning_of_month..Time.zone.now.end_of_month),
      last_month: build_stats(
        1.month.ago.beginning_of_month..1.month.ago.end_of_month
      )
    }
  end

  private

  def build_stats(range)
    scoped = calls.where(created_at: range)

    success = scoped.where(status: '手動送信成功').count
    failure = scoped.where(status: '手動送信失敗').count
    total   = success + failure

    rate =
      if total.zero?
        0
      else
        ((success.to_f / total) * 100).round(1)
      end

    {
      success: success,
      failure: failure,
      rate: rate
    }
  end
end