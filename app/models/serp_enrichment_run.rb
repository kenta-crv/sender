# frozen_string_literal: true

class SerpEnrichmentRun < ApplicationRecord
  STATUSES = %w[queued running serp web done error].freeze

  has_many :targets,
           class_name: "SerpEnrichmentRunTarget",
           dependent: :destroy,
           inverse_of: :run

  serialize :summary_json, JSON

  validates :run_id, presence: true, uniqueness: true
  validates :status, presence: true, inclusion: { in: STATUSES }

  def self.create_for_targets!(run_id:, industry:, limit:, targets:)
    target_records = Array(targets)

    transaction do
      run = create!(
        run_id: run_id,
        industry: industry.to_s,
        limit: limit.to_i,
        target_count: target_records.size,
        status: "queued",
        summary_json: {}
      )

      target_records.each_with_index do |customer, index|
        run.targets.create!(
          customer_id: customer.id,
          position: index + 1,
          company: customer.company.to_s,
          before_serp_status: customer.serp_status.to_s,
          before_tel: customer.tel.to_s,
          before_address: customer.address.to_s,
          before_url: customer.url.to_s,
          before_contact_url: customer.contact_url.to_s
        )
      end

      run
    end
  end

  def self.find_by_run_id(run_id)
    find_by(run_id: run_id.to_s)
  end

  def sidekiq_status
    return "unknown" if jid.blank?

    require "sidekiq/api"

    SerpSidekiqManager::SERP_QUEUE_NAMES.each do |queue_name|
      return "queued" if Sidekiq::Queue.new(queue_name).any? { |job| job.jid == jid }
    end

    workers = Sidekiq::Workers.new
    return "working" if workers.any? { |_process_id, _thread_id, work| work.dig("payload", "jid") == jid }

    status.presence || "unknown"
  rescue StandardError
    status.presence || "unknown"
  end

  def mark_status!(new_status, attrs = {})
    updates = attrs.merge(status: new_status)
    updates[:started_at] ||= Time.current if started_at.blank? && %w[running serp web].include?(new_status)
    updates[:finished_at] ||= Time.current if %w[done error].include?(new_status)
    update!(updates)
  end

  def update_progress!(attrs)
    update!(attrs.slice(:serp_total, :serp_completed, :web_total, :web_completed))
  end

  def complete!(done_count:, error_count:, summary: {})
    actual_success = targets.where(result_status: %w[updated url_only]).count
    actual_error = targets.where(result_status: %w[error no_candidate]).count

    update!(
      status: "done",
      finished_at: Time.current,
      summary_json: (summary || {}).merge(
        done_count: done_count.to_i,
        error_count: error_count.to_i,
        actual_success: actual_success,
        actual_error: actual_error
      )
    )
    Notification.create_for_serp!(run: self, client_id: client_id)
  end

  def fail!(message)
    update!(
      status: "error",
      error_message: message.to_s,
      finished_at: Time.current
    )
  end

  def bill_serp_api_usage!(count)
    billed = count.to_i
    return if billed <= 0
    return if client_id.blank?

    summary = summary_json.is_a?(Hash) ? summary_json : {}
    return if summary["serp_api_billed"].to_i.positive?

    client = Client.find_by(id: client_id)
    return if client.blank?

    client.monthly_usage_log.increment!(:serp_api_used, billed)
    update!(summary_json: summary.merge("serp_api_billed" => billed))
  end
end