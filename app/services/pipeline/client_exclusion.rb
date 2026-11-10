module Pipeline
  class ClientExclusion
    def matching_ids(customer_ids)
      ids = Array(customer_ids).map(&:to_i).reject(&:zero?)
      return [] if ids.empty?

      clients = Client.select(:company, :domain, :url).to_a
      names = clients.map { |client| normalize(client.company) }.reject(&:blank?).to_set
      domains = clients.flat_map { |client| [host(client.domain), host(client.url)] }.reject(&:blank?).to_set
      Customer.where(id: ids).select { |customer| match?(customer, names, domains) }.map(&:id)
    end

    private

    def match?(customer, names, domains)
      name = normalize(customer.company)
      return true if name.present? && names.include?(name)

      site = host(customer.url)
      site.present? && domains.include?(site)
    end

    def normalize(name)
      Customer.normalized_name(name).presence
    end

    def host(value)
      text = value.to_s.strip
      return if text.blank?

      text = "https://#{text}" unless text.include?("://")
      URI.parse(text).host.to_s.downcase.delete_prefix("www.").presence
    rescue URI::InvalidURIError
      nil
    end
  end
end
