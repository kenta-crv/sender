# frozen_string_literal: true

class SerpPipelineDbWorker
  include Sidekiq::Worker
  sidekiq_options queue: :serp_enrichment_admin, retry: 0

  BATCH_SIZE = ENV.fetch("SERP_BATCH_SIZE", "100").to_i.clamp(1, 500)

  # @param industry [String, nil]
  # @param customer_ids [Array<Integer>]
  # @param progress_run_id [String]
  # @param batch_offset [Integer] 全件 ID 配列内の開始位置（100件ずつ処理）
  def perform(industry = nil, customer_ids = nil, progress_run_id = nil, batch_offset = 0, queue_name = nil)
    queue_name = (queue_name || self.class.sidekiq_options["queue"]).to_s
    ids = Array(customer_ids).map(&:to_i).reject(&:zero?)
    batch_ids = ids.slice(batch_offset.to_i, BATCH_SIZE)
    return if batch_ids.empty?

    audit_run = SerpEnrichmentRun.find_by_run_id(progress_run_id) if progress_run_id.present?
    if audit_run&.status == "error"
      puts "[SerpPipelineDbWorker] run=#{progress_run_id} already failed - skip batch offset=#{batch_offset}"
      return
    end

    worker_jid = respond_to?(:jid) ? jid : nil
    audit_run&.update!(jid: worker_jid.to_s) if worker_jid.present? && audit_run&.jid.blank?
    audit_run&.mark_status!("running") if audit_run&.status == "queued"

    batch_num = (batch_offset.to_i / BATCH_SIZE) + 1
    batch_total = (ids.size.to_f / BATCH_SIZE).ceil
    finalize_run = (batch_offset.to_i + batch_ids.size) >= ids.size

    puts "[SERP run=#{progress_run_id} jid=#{worker_jid}] [SerpPipelineDbWorker] batch #{batch_num}/#{batch_total} size=#{batch_ids.size} finalize=#{finalize_run}"

    BrightData::Pipeline.execute_from_db(
      industry: industry,
      limit: batch_ids.size,
      customer_ids: batch_ids,
      progress_run_id: progress_run_id,
      jid: worker_jid,
      detect_contact: false,
      dry_run: false,
      finalize_run: finalize_run
    )

    audit_run&.reload
    if audit_run&.status == "error"
      puts "[SerpPipelineDbWorker] batch #{batch_num} failed - stop chaining"
      return
    end

    next_offset = batch_offset.to_i + batch_ids.size
    return if next_offset >= ids.size

    self.class.set(queue: queue_name).perform_async(industry, ids, progress_run_id, next_offset, queue_name)
  rescue => e
    audit_run&.fail!(e.message)
    raise
  end
end
