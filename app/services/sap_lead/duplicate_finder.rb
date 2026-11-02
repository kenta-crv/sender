module SapLead
  class DuplicateFinder
    def initialize
      @loaded = false
      @by_name = {}
      @by_tel = {}
      @by_domain = {}
    end

    def find(company:, tel: nil, url: nil)
      load_customers
      candidates = []
      domain_key = domain(url)
      tel_key = digits(tel)
      name_key = Customer.normalized_name(company)
      candidates << @by_domain[domain_key] if domain_key
      candidates << @by_tel[tel_key] if tel_key
      candidates << @by_name[name_key] if name_key.present?
      candidates.compact.min_by(&:id)
    end

    def remember(customer)
      load_customers
      index_customer(customer)
    end

    private

    def load_customers
      return if @loaded

      @loaded = true
      Customer.where(client_id: nil).find_each { |customer| index_customer(customer) }
    end

    def index_customer(customer)
      return if customer.client_id.present?

      name = Customer.normalized_name(customer.company)
      keep(@by_name, name, customer) if name.present?
      tel = digits(customer.tel)
      keep(@by_tel, tel, customer) if tel
      host = domain(customer.url)
      keep(@by_domain, host, customer) if host
    end

    def keep(map, key, customer)
      current = map[key]
      map[key] = customer if current.nil? || customer.id < current.id
    end

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
