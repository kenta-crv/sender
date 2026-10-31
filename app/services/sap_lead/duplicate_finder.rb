module SapLead
  class DuplicateFinder
    def find(company:, tel: nil, url: nil)
      target_name = Customer.normalized_name(company)
      target_tel = digits(tel)
      target_domain = domain(url)

      Customer.find_each do |customer|
        if target_domain.present? && domain(customer.url) == target_domain
          return customer
        end
        if target_tel.present? && digits(customer.tel) == target_tel
          return customer
        end
        candidate = Customer.normalized_name(customer.company)
        return customer if Customer.name_similarity?(target_name, candidate)
      end
      nil
    end

    private

    def digits(value)
      number = value.to_s.gsub(/\D/, "")
      number.presence
    end

    def domain(url)
      return nil if url.blank?

      host = URI.parse(url).host
      host.to_s.downcase.sub(/\Awww\./, "").presence
    rescue URI::InvalidURIError
      nil
    end
  end
end
