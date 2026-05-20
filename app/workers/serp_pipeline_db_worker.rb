# frozen_string_literal: true

require "fileutils"

class SerpPipelineDbWorker
  include Sidekiq::Worker
  sidekiq_options queue: :serp_enrichment, retry: 1

  def perform(industry = nil, limit = 100, customer_ids = nil, progress_run_id = nil)
    worker_jid = respond_to?(:jid) ? jid : nil
    audit_run = SerpEnrichmentRun.find_by_run_id(progress_run_id) if progress_run_id.present?
    audit_run&.update!(jid: worker_jid.to_s) if worker_jid.present? && audit_run&.jid.blank?
    audit_run&.mark_status!("running")

    prefix = "[SERP run=#{progress_run_id} jid=#{worker_jid}]"
    log_path = progress_run_id.present? ? SerpEnrichmentRun.log_path_for(progress_run_id) : nil
    reset_shared_log(progress_run_id, worker_jid) if progress_run_id.present?
    if log_path.present?
      BrightData::LogContext.reset_file(log_path)
      BrightData::LogContext.file_puts(log_path, "SERP run_id=#{progress_run_id} / JID=#{worker_jid}")
    end
    BrightData::LogContext.with_context(prefix: prefix, file_path: log_path) do
      BrightData::LogContext.puts "[SerpPipelineDbWorker] DB mode: legacy contact crawl disabled"
    end
    BrightData::Pipeline.execute_from_db(
      industry: industry,
      limit: limit,
      customer_ids: customer_ids,
      progress_run_id: progress_run_id,
      jid: worker_jid,
      detect_contact: false,
      dry_run: false
    )
  rescue => e
    audit_run&.fail!(e.message)
    raise
  end

  private

  def reset_shared_log(progress_run_id, worker_jid)
    path = SerpSidekiqManager::LOG_PATH
    FileUtils.mkdir_p(path.dirname)
    File.write(
      path,
      [
        "=== 最新SERP実行ログ ===",
        "run_id=#{progress_run_id} / JID=#{worker_jid}",
        "開始=#{BrightData::Pipeline.japan_time_label}",
        ""
      ].join("\n")
    )
  end
end
