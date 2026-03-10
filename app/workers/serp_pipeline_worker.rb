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

class SerpPipelineDbWorker
  include Sidekiq::Worker
  sidekiq_options queue: :serp, retry: 1

  # UI経由で非同期実行するワーカー
  # @param industry [String|nil] 業種フィルタ
  # @param limit [Integer] 処理件数上限
  def perform(industry = nil, limit = 100)
    BrightData::Pipeline.execute_from_db(
      industry: industry,
      limit: limit,
      detect_contact: true,
      dry_run: false
    )
  end
end
