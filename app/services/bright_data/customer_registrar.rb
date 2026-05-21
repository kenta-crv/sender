# frozen_string_literal: true

module BrightData
  class CustomerRegistrar
    def self.register(normalized_companies)
      stats = { imported: 0, skipped_dup: 0, skipped_blank: 0, errors: 0 }

      existing_companies = Customer.pluck(:company).compact.map(&:strip).to_set
      existing_normalized_companies = existing_companies.map { |name| UrlPolicy.normalize_company_name(name) }.compact.to_set
      existing_urls = Customer.pluck(:url).compact.map(&:strip).to_set

      normalized_companies.each do |data|
        if data[:company].blank? && data[:url].blank?
          stats[:skipped_blank] += 1
          next
        end

        normalized_company = UrlPolicy.normalize_company_name(data[:company])
        if data[:company].present? && (existing_companies.include?(data[:company]) || existing_normalized_companies.include?(normalized_company))
          stats[:skipped_dup] += 1
          next
        end
        if data[:url].present? && existing_urls.include?(data[:url])
          stats[:skipped_dup] += 1
          next
        end

        begin
          Customer.create!(
            company: data[:company], tel: data[:tel], address: data[:address],
            url: data[:url], contact_url: data[:contact_url],
            industry: data[:industry], serp_status: "serp_imported"
          )
          existing_companies << data[:company] if data[:company].present?
          existing_normalized_companies << normalized_company if normalized_company.present?
          existing_urls << data[:url] if data[:url].present?
          stats[:imported] += 1
        rescue => e
          stats[:errors] += 1
          puts "[Registrar] Error: #{e.message}"
        end
      end

      puts "\n=== 登録結果 ==="
      stats.each { |k, v| puts "  #{k}: #{v}" }
      stats
    end
  end
end
