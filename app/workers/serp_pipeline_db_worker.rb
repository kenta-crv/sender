# frozen_string_literal: true

class SerpPipelineDbWorker
  include Sidekiq::Worker
  sidekiq_options queue: :serp_enrichment_admin, retry: 0

  BATCH_SIZE = ENV.fetch("SERP_BATCH_SIZE", "100").to_i.clamp(1, 500)

  # @param industry [String, nil]
  # @param customer_ids [Array<Integer>, nil] 初回ジョブ用。2バッチ目以降は audit_run.targets から復元する
  # @param progress_run_id [String]
  # @param batch_offset [Integer] 全件 ID 配列内の開始位置（100件ずつ処理）
  # @param queue_name [String, nil]
  def perform(industry = nil, customer_ids = nil, progress_run_id = nil, batch_offset = 0, queue_name = nil)
    queue_name = (queue_name || self.class.sidekiq_options["queue"]).to_s
    audit_run = SerpEnrichmentRun.find_by_run_id(progress_run_id) if progress_run_id.present?

    if audit_run&.status == "error"
      puts "[SerpPipelineDbWorker] run=#{progress_run_id} already failed - skip batch offset=#{batch_offset}"
      return
    end

    ids = resolve_target_ids(audit_run, customer_ids)
    batch_offset = batch_offset.to_i
    batch_ids = ids.slice(batch_offset, BATCH_SIZE)
    return if batch_ids.empty?

    industry = industry.presence || audit_run&.industry

    if audit_run&.status == "done" && (batch_offset + batch_ids.size) < ids.size
      Rails.logger.warn(
        "[SerpPipelineDbWorker] run=#{progress_run_id} marked done early at offset=#{batch_offset}; reopening for remaining #{ids.size - batch_offset} targets"
      )
      audit_run.mark_status!("running", finished_at: nil)
    end

    worker_jid = respond_to?(:jid) ? jid : nil
    audit_run&.update!(jid: worker_jid.to_s) if worker_jid.present? && audit_run&.jid.blank?
    audit_run&.mark_status!("running") if audit_run&.status == "queued"

    batch_num = (batch_offset / BATCH_SIZE) + 1
    batch_total = (ids.size.to_f / BATCH_SIZE).ceil
    finalize_run = (batch_offset + batch_ids.size) >= ids.size

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

    next_offset = batch_offset + batch_ids.size
    return if next_offset >= ids.size

    enqueue_next_batch!(
      industry: industry,
      progress_run_id: progress_run_id,
      next_offset: next_offset,
      queue_name: queue_name,
      audit_run: audit_run
    )
  rescue => e
    audit_run&.fail!(e.message)
    raise
  end

  def self.resolve_target_ids(audit_run, customer_ids)
    if audit_run&.targets&.exists?
      audit_run.targets.order(:position).pluck(:customer_id)
    else
      Array(customer_ids).map(&:to_i).reject(&:zero?)
    end
  end

  private

  def resolve_target_ids(audit_run, customer_ids)
    self.class.resolve_target_ids(audit_run, customer_ids)
  end

  def enqueue_next_batch!(industry:, progress_run_id:, next_offset:, queue_name:, audit_run:)
    next_jid = self.class.set(queue: queue_name.to_sym).perform_async(
      industry,
      nil,
      progress_run_id,
      next_offset,
      queue_name
    )

    return if next_jid.present?

    message = "次バッチのエンキューに失敗しました (offset=#{next_offset})"
    Rails.logger.error("[SerpPipelineDbWorker] #{message} run=#{progress_run_id}")
    audit_run&.fail!(message)
    raise message
  end
end
