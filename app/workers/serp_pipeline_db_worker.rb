# frozen_string_literal: true

class SerpPipelineDbWorker
  include Sidekiq::Worker
  sidekiq_options queue: :serp_enrichment, retry: 1

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
