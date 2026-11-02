module SapLead
  class Registrar
    def initialize(logger: Rails.logger)
      @logger = logger
      @finder = DuplicateFinder.new
    end

    def run
      stats = { created: 0, appended: 0 }
      JobPosting.where(status: "resolved").find_each do |posting|
        register_one(posting, stats)
      end
      @logger.info("[SapLeadRegister] #{stats.inspect}")
      stats
    end

    private

    def normalize_company(name)
      name.to_s.unicode_normalize(:nfkc)
    end

    def register_one(posting, stats)
      official_name = normalize_company(posting.official_name.presence || posting.company_raw)
      existing = @finder.find(company: official_name, url: posting.official_url)
      vars = {
        "job_title" => posting.title.to_s,
        "company" => official_name.to_s,
        "area" => HeadquartersArea.extract(posting.headquarters_address)
      }.to_json

      if existing
        existing.add_business!(Kyujinbox::INDUSTRY)
        existing.update!(template_vars: vars)
        if existing.url.blank? && posting.official_url.present?
          existing.update!(url: posting.official_url)
          @finder.remember(existing)
        end
        kind = "appended"
        customer = existing
        stats[:appended] += 1
      else
        customer = Customer.create!(
          company: official_name,
          address: posting.headquarters_address,
          url: posting.official_url,
          business: Kyujinbox::INDUSTRY,
          template_vars: vars,
          client_id: nil
        )
        @finder.remember(customer)
        kind = "created"
        stats[:created] += 1
      end

      posting.update!(
        customer_id: customer.id,
        status: "registered",
        registration_kind: kind,
        registered_at: Time.current
      )
    rescue StandardError => e
      @logger.error("[SapLeadRegister] job_posting=#{posting.id} #{e.class}: #{e.message}")
    end
  end
end
