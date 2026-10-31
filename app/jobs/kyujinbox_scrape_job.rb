class KyujinboxScrapeJob < ApplicationJob
  def perform(start_urls: nil, max_pages: nil, page_interval: nil)
    Kyujinbox::Importer.new(page_interval: page_interval.nil? ? Kyujinbox::PAGE_INTERVAL : page_interval).run(
      start_urls: start_urls,
      max_pages: max_pages
    )
  end
end
