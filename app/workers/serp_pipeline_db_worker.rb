# frozen_string_literal: true

class SerpPipelineDbWorker
  include Sidekiq::Worker
  sidekiq_options queue: :serp_enrichment, retry: 1

  # UI経由で非同期実行するワーカー
  # @param industry [String|nil] 業種フィルタ
  # @param limit [Integer] 処理件数上限
  def perform(industry = nil, limit = 100, customer_ids = nil, progress_run_id = nil)
    puts "[SerpPipelineDbWorker] DB mode: legacy contact crawl disabled"
    BrightData::Pipeline.execute_from_db(
      industry: industry,
      limit: limit,
      customer_ids: customer_ids,
      progress_run_id: progress_run_id,
      detect_contact: false,
      dry_run: false
    )
  end
end
