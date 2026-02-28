# app/workers/extract_company_info_worker.rb
class ExtractCompanyInfoWorker
  include Sidekiq::Worker

  def perform(customer_id)
    customer = Customer.find(customer_id)

    query = "#{customer.company} #{customer.address} 会社概要 -求人 -採用"

    serp = BrightData::SerpClient.new(
      api_key: ENV["BRIGHT_DATA_API_KEY"]
    ).search(query: query)

    urls = UrlCandidateExtractor.extract(serp)
    raise "URL候補なし" if urls.empty?

    top_page = TopPageSelector.select(urls)

    html = Net::HTTP.get(URI(top_page))

    info = CompanyInfoExtractor.new(
      html,
      customer: customer
    ).extract

    customer.update!(
      company: info[:company],
      tel: info[:tel],
      address: info[:address],
      url: top_page,
      contact_url: info[:contact_url],
      status: "success"
    )
  rescue => e
    customer.update!(
      status: "failed"
    )
    Rails.logger.error(e.message)
  end
end
