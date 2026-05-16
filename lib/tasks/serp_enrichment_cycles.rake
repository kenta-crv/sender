# frozen_string_literal: true

namespace :serp do
  desc "Recheck existing official URLs, then continue BrightData SERP cycles"
  task enrichment_cycles: :environment do
    batch_size = ENV.fetch("BATCH", "5").to_i
    existing_cycles = ENV.fetch("EXISTING_CYCLES", "100").to_i
    new_serp_cycles = ENV.fetch("NEW_SERP_CYCLES", "100").to_i
    csv_path = ENV["CSV_PATH"]

    summary = BrightData::SerpEnrichmentCycleRunner.run(
      batch_size: batch_size,
      existing_cycles: existing_cycles,
      new_serp_cycles: new_serp_cycles,
      csv_path: csv_path
    )

    puts "[SerpCycle] summary=#{summary.inspect}"
  end
end
