# frozen_string_literal: true

class SerpPipelineWorker
  include Sidekiq::Worker
  sidekiq_options queue: :serp, retry: 1

  def perform(csv_path, keyword_column = "company")
    BrightData::Pipeline.execute(
      csv_path: csv_path, keyword_column: keyword_column,
      delay_between: 2, detect_contact: true, dry_run: false
    )
  end
end


