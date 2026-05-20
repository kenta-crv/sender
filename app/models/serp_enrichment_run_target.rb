# frozen_string_literal: true

class SerpEnrichmentRunTarget < ApplicationRecord
  RESULT_STATUSES = %w[pending updated url_only no_candidate excluded no_update error].freeze

  belongs_to :run,
             class_name: "SerpEnrichmentRun",
             foreign_key: :serp_enrichment_run_id,
             inverse_of: :targets
  belongs_to :customer, optional: true

  serialize :update_keys, Array

  validates :customer_id, presence: true
  validates :result_status, presence: true, inclusion: { in: RESULT_STATUSES }

  def self.for_run(run_id)
    joins(:run).where(serp_enrichment_runs: { run_id: run_id.to_s })
  end

  def refresh_after!(customer:, result_status:, candidate_count:, selected_url: nil, update_keys: [], error_message: nil)
    update!(
      result_status: result_status,
      candidate_count: candidate_count.to_i,
      selected_url: selected_url.to_s.presence,
      update_keys: Array(update_keys).map(&:to_s).uniq,
      error_message: error_message.to_s.presence,
      after_serp_status: customer&.effective_serp_status.to_s,
      after_tel: customer&.tel.to_s,
      after_address: customer&.address.to_s,
      after_url: customer&.url.to_s,
      after_contact_url: customer&.contact_url.to_s
    )
  end

  def update_keys_label
    Array(update_keys).reject(&:blank?).join(", ")
  end
end
