# frozen_string_literal: true

module BrightData
  class ContactUrlEnricher
    # @param companies [Array<Hash>] CompanyExtractor の戻り値
    # @param headless [Boolean]
    def self.enrich(companies, headless: true)
      detector = ContactUrlDetector.new(debug: true, headless: headless)

      companies.each_with_index do |company, idx|
        next if company[:url].blank?
        next if company[:contact_url].present?

        puts "[ContactUrlEnricher] #{idx + 1}/#{companies.size}: #{company[:company]} (#{company[:url]})"

        mock_customer = OpenStruct.new(company: company[:company], url: company[:url])

        begin
          result = detector.detect(mock_customer)
          company[:contact_url] = result[:contact_url]
          puts "  -> #{result[:status]}: #{result[:contact_url] || result[:message]}"
        rescue => e
          puts "  -> ERROR: #{e.message}"
        end

        sleep(1)
      end

      companies
    end
  end
end
