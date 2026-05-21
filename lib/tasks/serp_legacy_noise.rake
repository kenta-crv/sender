# frozen_string_literal: true

require "csv"

namespace :serp do
  desc "Export legacy serp_imported rows that look like job/directory/noisy SERP imports"
  task export_legacy_noise: :environment do
    timestamp = Time.current.strftime("%Y%m%d_%H%M%S")
    path = Rails.root.join("tmp", "serp_legacy_noise_#{timestamp}.csv")

    imported = Customer.where(serp_status: "serp_imported").to_a
    normalized_counts = imported.each_with_object(Hash.new(0)) do |customer, counts|
      normalized = BrightData::UrlPolicy.normalize_company_name(customer.company)
      counts[normalized] += 1 if normalized.present?
    end

    rows = imported.filter_map do |customer|
      normalized = BrightData::UrlPolicy.normalize_company_name(customer.company)
      reasons = []
      reasons << "excluded_url" if customer.url.present? && BrightData::UrlPolicy.excluded_url?(customer.url, title: customer.company)
      reasons << "company_name_noise" if normalized.present? && normalized != customer.company.to_s.strip
      reasons << "duplicate_normalized_company" if normalized.present? && normalized_counts[normalized] > 1

      next if reasons.empty?

      [
        customer.id,
        customer.company,
        normalized,
        customer.url,
        customer.contact_url,
        customer.address,
        customer.serp_status,
        reasons.join("|"),
        customer.updated_at
      ]
    end

    CSV.open(path, "w", encoding: "UTF-8") do |csv|
      csv << %w[id company normalized_company url contact_url address serp_status reasons updated_at]
      rows.each { |row| csv << row }
    end

    puts "Exported #{rows.size} rows to #{path}"
  end
end
