class KyujinboxBackfillJob < ApplicationJob
  def perform
    Kyujinbox::Backfill.new.run
  end
end
