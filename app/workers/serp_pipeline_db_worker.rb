# frozen_string_literal: true

class SerpPipelineDbWorker
  include Sidekiq::Worker
  sidekiq_options queue: :serp_enrichment_admin, retry: 0

  BATCH_SIZE = ENV.fetch("SERP_BATCH_SIZE", "100").to_i.clamp(1, 500)
  SHUTDOWN_ERRORS = [Sidekiq::Shutdown, Interrupt, SignalException].freeze
  RESUMABLE_ERROR_PATTERN = /Sidekiq::Shutdown|Interrupt|SignalException|interrupted/i.freeze

  # @param industry [String, nil]
  # @param customer_ids [Array<Integer>, nil] 初回ジョブ用。2バッチ目以降は audit_run.targets から復元する
  # @param progress_run_id [String]
  # @param batch_offset [Integer] 全件 ID 配列内の開始位置（100件ずつ処理）
  # @param queue_name [String, nil]
  def perform(industry = nil, customer_ids = nil, progress_run_id = nil, batch_offset = 0, queue_name = nil)
    queue_name = (queue_name || self.class.sidekiq_options["queue"]).to_s
    audit_run = SerpEnrichmentRun.find_by_run_id(progress_run_id) if progress_run_id.present?

    ids = resolve_target_ids(audit_run, customer_ids)
    batch_offset = batch_offset.to_i
    batch_ids = ids.slice(batch_offset, BATCH_SIZE)
    return if batch_ids.empty?

    if audit_run&.status == "error"
      if resumable_interrupt?(audit_run)
        reopen_interrupted_batch!(audit_run, batch_ids)
      else
        puts "[SerpPipelineDbWorker] run=#{progress_run_id} already failed - skip batch offset=#{batch_offset}"
        return
      end
    end

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

    result = BrightData::Pipeline.execute_from_db(
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
    if audit_run&.status == "error" || result.is_a?(Hash) && result[:stop_chaining]
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
  rescue *SHUTDOWN_ERRORS => e
    # 永久 error にせず、未完了を戻して同じ offset を再投入
    Rails.logger.warn("[SerpPipelineDbWorker] #{e.class} at offset=#{batch_offset}; re-enqueue same batch")
    puts "[SerpPipelineDbWorker] interrupted - re-enqueue offset=#{batch_offset}"
    restore_incomplete_batch!(batch_ids)
    if audit_run
      audit_run.update!(
        status: "running",
        error_message: nil,
        finished_at: nil
      )
    end
    begin
      self.class.set(queue: queue_name.to_sym).perform_async(
        industry,
        nil,
        progress_run_id,
        batch_offset,
        queue_name
      )
    rescue => enqueue_error
      Rails.logger.error("[SerpPipelineDbWorker] failed to re-enqueue after shutdown: #{enqueue_error.message}")
    end
    raise
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

  def self.resumable_interrupt?(audit_run)
    audit_run&.error_message.to_s.match?(RESUMABLE_ERROR_PATTERN)
  end

  # done 以外（queued / error の誤残存含む）を未処理に戻す
  def self.restore_incomplete_batch!(batch_ids)
    ids = Array(batch_ids).map(&:to_i).reject(&:zero?).uniq
    return if ids.empty?

    updated = Customer.where(id: ids).where.not(serp_status: "serp_done").update_all(
      serp_status: nil,
      updated_at: Time.current
    )
    puts "[SerpPipelineDbWorker] restored incomplete→null count=#{updated} ids=#{ids.size}"
    updated
  end

  private

  def resolve_target_ids(audit_run, customer_ids)
    self.class.resolve_target_ids(audit_run, customer_ids)
  end

  def resumable_interrupt?(audit_run)
    self.class.resumable_interrupt?(audit_run)
  end

  def reopen_interrupted_batch!(audit_run, batch_ids)
    puts "[SerpPipelineDbWorker] reopening interrupted run=#{audit_run.run_id}"
    audit_run.update!(status: "running", error_message: nil, finished_at: nil)
    restore_incomplete_batch!(batch_ids)
  end

  def restore_incomplete_batch!(batch_ids)
    self.class.restore_incomplete_batch!(batch_ids)
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
