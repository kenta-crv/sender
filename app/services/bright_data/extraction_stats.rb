# frozen_string_literal: true

module BrightData
  class ExtractionStats
    def self.record(companies, industry_label:, total_queries:, serp_errors: 0)
      total = companies.size

      ExtractTracking.create!(
        industry: industry_label,
        total_count: total_queries,
        success_count: total,
        failure_count: serp_errors,
        status: "completed"
      )

      stats = {
        company: companies.count { |c| c[:company].present? },
        tel:     companies.count { |c| c[:tel].present? },
        address: companies.count { |c| c[:address].present? },
        url:     companies.count { |c| c[:url].present? },
        contact: companies.count { |c| c[:contact_url].present? },
        industry: companies.count { |c| c[:industry].present? }
      }

      puts "\n=== SERP抽出率（検索結果から直接取得）==="
      puts "SERPクエリ: #{total_queries} / エラー: #{serp_errors}"
      puts "抽出企業: #{total}"
      stats.each { |k, v| puts "  #{k}: #{v}/#{total} (#{total.zero? ? 0 : (v.to_f/total*100).round(1)}%)" }

      stats
    end
  end
end
