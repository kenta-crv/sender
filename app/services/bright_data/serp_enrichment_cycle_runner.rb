# frozen_string_literal: true

require "csv"
require "fileutils"
require "set"
require "timeout"

module BrightData
  class SerpEnrichmentCycleRunner
    DEFAULT_BATCH_SIZE = 5
    DEFAULT_EXISTING_CYCLES = 100
    DEFAULT_NEW_SERP_CYCLES = 100
    DEFAULT_WEB_TIMEOUT = ENV.fetch("SERP_CYCLE_WEB_TIMEOUT_SECONDS", "45").to_f

    HEADER = %w[
      timestamp phase cycle customer_id company url before_tel after_tel
      before_address after_address before_contact_url after_contact_url
      matched status reason updates
    ].freeze

    def self.run(batch_size: DEFAULT_BATCH_SIZE,
                 existing_cycles: DEFAULT_EXISTING_CYCLES,
                 new_serp_cycles: DEFAULT_NEW_SERP_CYCLES,
                 csv_path: nil)
      new(
        batch_size: batch_size,
        existing_cycles: existing_cycles,
        new_serp_cycles: new_serp_cycles,
        csv_path: csv_path
      ).run
    end

    def initialize(batch_size:, existing_cycles:, new_serp_cycles:, csv_path:)
      @batch_size = batch_size.to_i.clamp(1, 50)
      @existing_cycles = existing_cycles.to_i.clamp(0, 1_000)
      @new_serp_cycles = new_serp_cycles.to_i.clamp(0, 1_000)
      @csv_path = csv_path.presence || Rails.root.join("tmp", "serp_enrichment_cycles_#{Time.current.strftime('%Y%m%d_%H%M%S')}.csv").to_s
      @seen_existing_ids = Set.new
      @stats = Hash.new(0)
    end

    attr_reader :csv_path

    def run
      FileUtils.mkdir_p(File.dirname(csv_path))
      CSV.open(csv_path, "w", encoding: "UTF-8") { |csv| csv << HEADER }

      existing_cycles_done = run_existing_phase(max_cycles: @existing_cycles, phase: "existing_url")
      new_serp_cycles_done = 0

      if existing_candidates_remaining?
        puts "[SerpCycle] existing URL candidates remain after #{existing_cycles_done} cycles; skip new SERP phase."
        return summary(existing_cycles_done: existing_cycles_done, new_serp_cycles_done: new_serp_cycles_done)
      end

      @new_serp_cycles.times do |index|
        before_error_count = Customer.where(serp_status: "serp_error").count
        result = Pipeline.execute_from_db(limit: @batch_size)
        new_serp_cycles_done += 1
        write_meta_row("new_serp", index + 1, result)

        break if result[:targets].to_i.zero?

        # Newly URL-filled rows are immediately inspected with the same extractor path.
        run_existing_phase(max_cycles: 1, phase: "new_serp_recheck")

        after_error_count = Customer.where(serp_status: "serp_error").count
        if after_error_count > before_error_count
          puts "[SerpCycle] new SERP produced serp_error rows; stopping new SERP phase."
          break
        end
      end

      summary(existing_cycles_done: existing_cycles_done, new_serp_cycles_done: new_serp_cycles_done)
    end

    private

    def run_existing_phase(max_cycles:, phase:)
      cycles_done = 0
      max_cycles.times do |index|
        batch = existing_candidates
        break if batch.empty?

        cycles_done += 1
        puts "[SerpCycle] #{phase} cycle #{index + 1}: #{batch.size}件"
        batch.each { |customer| recheck_customer(customer, phase: phase, cycle: index + 1) }
      end
      cycles_done
    end

    def existing_candidates
      existing_candidate_scope.limit(@batch_size * 200).to_a.select do |customer|
        next false if @seen_existing_ids.include?(customer.id)
        next false unless UrlPolicy.official_url?(customer.url, title: customer.company)

        needs_primary_data?(customer)
      end.first(@batch_size)
    end

    def existing_candidates_remaining?
      existing_candidates.any?
    end

    def existing_candidate_scope
      Customer.where(serp_status: "serp_done")
              .where.not(url: [nil, ""])
              .order(updated_at: :desc, id: :asc)
    end

    def needs_primary_data?(customer)
      customer.tel.to_s.strip.blank? || Pipeline.send(:address_score, customer.address).zero?
    end

    def recheck_customer(customer, phase:, cycle:)
      @seen_existing_ids << customer.id
      before = snapshot(customer)
      company = { url: customer.url, company: customer.company, title: customer.company }

      web_data = Timeout.timeout(DEFAULT_WEB_TIMEOUT) do
        WebEnricher.enrich_from_url(customer.url, customer)
      end
      updates = Pipeline.send(:build_web_updates, customer, company, web_data)
      apply_updates(customer, updates)
      customer.reload

      status = updates.any? ? "updated" : "no_update"
      reason = reason_for(customer, before, web_data, updates)
      @stats[status] += 1
      write_customer_row(phase, cycle, before, customer, web_data, status, reason, updates)
    rescue => e
      customer.reload
      @stats["error"] += 1
      write_customer_row(phase, cycle, before || snapshot(customer), customer, {}, "error", "#{e.class}: #{e.message}", {})
    end

    def apply_updates(customer, updates)
      return if updates.blank?

      customer.update_columns(updates.merge(updated_at: Time.current))
    end

    def snapshot(customer)
      {
        id: customer.id,
        company: customer.company.to_s,
        url: customer.url.to_s,
        tel: customer.tel.to_s,
        address: customer.address.to_s,
        contact_url: customer.contact_url.to_s
      }
    end

    def reason_for(customer, before, web_data, updates)
      return "company_mismatch" if web_data[:matched] == false
      return "updated_#{updates.keys.join('_')}" if updates.any?
      return "tel_and_address_still_missing" if customer.tel.blank? && Pipeline.send(:address_score, customer.address).zero?
      return "tel_still_missing" if customer.tel.blank?
      return "address_still_insufficient" if Pipeline.send(:address_score, customer.address).zero?
      return "unchanged" if before[:tel] == customer.tel.to_s && before[:address] == customer.address.to_s

      "not_better_than_existing"
    end

    def write_customer_row(phase, cycle, before, customer, web_data, status, reason, updates)
      CSV.open(csv_path, "a", encoding: "UTF-8") do |csv|
        csv << [
          Time.current.iso8601,
          phase,
          cycle,
          customer.id,
          customer.company,
          customer.url,
          before[:tel],
          customer.tel,
          before[:address],
          customer.address,
          before[:contact_url],
          customer.contact_url,
          web_data[:matched],
          status,
          reason,
          updates.keys.join("|")
        ]
      end
    end

    def write_meta_row(phase, cycle, result)
      CSV.open(csv_path, "a", encoding: "UTF-8") do |csv|
        csv << [
          Time.current.iso8601,
          phase,
          cycle,
          "",
          "BrightData::Pipeline.execute_from_db",
          "",
          "",
          "",
          "",
          "",
          "",
          "",
          "",
          "pipeline",
          "targets=#{result[:targets]} extracted=#{result[:extracted]}",
          result.inspect
        ]
      end
    end

    def summary(existing_cycles_done:, new_serp_cycles_done:)
      {
        csv_path: csv_path,
        existing_cycles_done: existing_cycles_done,
        new_serp_cycles_done: new_serp_cycles_done,
        stats: @stats.dup
      }
    end
  end
end
