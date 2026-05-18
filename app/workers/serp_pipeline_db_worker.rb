# frozen_string_literal: true

class SerpPipelineDbWorker
  include Sidekiq::Worker
  sidekiq_options queue: :serp_enrichment, retry: 1

  def perform(industry = nil, limit = 100, customer_ids = nil, progress_run_id = nil)
    worker_jid = respond_to?(:jid) ? jid : nil
    audit_run = SerpEnrichmentRun.find_by_run_id(progress_run_id) if progress_run_id.present?
    audit_run&.update!(jid: worker_jid.to_s) if worker_jid.present? && audit_run&.jid.blank?
    audit_run&.mark_status!("running")

    puts "[SERP run=#{progress_run_id} jid=#{worker_jid}] [SerpPipelineDbWorker] DB mode: legacy contact crawl disabled"
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
end
