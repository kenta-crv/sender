module SapLead
  class DuplicateFinder
    def initialize
      @loaded = false
      @by_name = {}
      @by_tel = {}
      @by_domain = {}
      @name_groups = Hash.new { |groups, key| groups[key] = [] }
    end

    def find(company:, tel: nil, url: nil)
      load_customers
      candidates = []
      domain_key = domain(url)
      tel_key = digits(tel)
      matched_name = name_key(company)
      candidates << @by_domain[domain_key] if domain_key
      candidates << @by_tel[tel_key] if tel_key
      candidates << @by_name[matched_name] if matched_name.present?
      candidates.compact.min_by(&:id)
    end

    def find_unique_by_name(company)
      load_customers
      key = name_key(company)
      return nil if key.blank?

      group = @name_groups.fetch(key, nil)
      return nil if group.nil? || group.size != 1

      group.first
    end

    def remember(customer)
      load_customers
      index_customer(customer)
    end

    private

    def load_customers
      return if @loaded

      @loaded = true
      Customer.find_each { |customer| index_customer(customer) }
    end

    def index_customer(customer)
      name = name_key(customer.company)
      if name.present?
        @name_groups[name] << customer unless @name_groups[name].any? { |row| row.id == customer.id }
        keep(@by_name, name, customer)
      end
      tel = digits(customer.tel)
      keep(@by_tel, tel, customer) if tel
      host = domain(customer.url)
      keep(@by_domain, host, customer) if host
    end

    def keep(map, key, customer)
      current = map[key]
      map[key] = customer if current.nil? || customer.id < current.id
    end

    def name_key(company)
      SapLead::CompanyName.normalize(company).presence
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
