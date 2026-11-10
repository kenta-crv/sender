module SapLead
  class Registrar
    def initialize(logger: Rails.logger)
      @logger = logger
      @finder = DuplicateFinder.new
    end

    LINK_SKIP_REASONS = %w[同名複数 法人番号なし].freeze

    def run(campaign_key: nil)
      stats = { created: 0, appended: 0 }
      resolved = JobPosting.where(status: "resolved")
      skipped = JobPosting.where(status: "skipped", skip_reason: LINK_SKIP_REASONS, customer_id: nil)
      if campaign_key.present?
        resolved = resolved.where(campaign_key: campaign_key)
        skipped = skipped.where(campaign_key: campaign_key)
      end
      resolved.find_each { |posting| register_one(posting, stats) }
      skipped.find_each { |posting| link_skipped(posting, stats) }
      @logger.info("[SapLeadRegister] #{stats.inspect}")
      stats
    end

    private

    def business_for(posting)
      Pipeline::Campaign.find(posting.campaign_key)&.business.presence || Kyujinbox::INDUSTRY
    end

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
        existing.add_business!(business_for(posting))
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
          business: business_for(posting),
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

    def link_skipped(posting, stats)
      name = posting.company_raw.presence || posting.company_clean
      existing = @finder.find_unique_by_name(name)
      return if existing.nil?

      official_name = normalize_company(name)
      existing.add_business!(business_for(posting))
      existing.update!(
        template_vars: {
          "job_title" => posting.title.to_s,
          "company" => official_name.to_s,
          "area" => HeadquartersArea.extract(posting.headquarters_address)
        }.to_json
      )
      if existing.url.blank? && posting.official_url.present?
        existing.update!(url: posting.official_url)
        @finder.remember(existing)
      end
      posting.update!(
        customer_id: existing.id,
        status: "registered",
        registration_kind: "appended",
        registered_at: Time.current
      )
      stats[:appended] += 1
    rescue StandardError => e
      @logger.error("[SapLeadRegister] job_posting=#{posting.id} #{e.class}: #{e.message}")
    end
  end
end
