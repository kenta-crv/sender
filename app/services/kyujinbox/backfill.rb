module Kyujinbox
  class Backfill
    MAX_PAGES = 100
    PAGE_INTERVAL = 3

    def initialize(campaign: Pipeline::Campaign.sap, client: Kyujinbox::Client.new, page_interval: PAGE_INTERVAL, logger: Rails.logger)
      @campaign = campaign
      @page_interval = page_interval
      @importer = Importer.new(client: client, page_interval: 0, logger: logger, campaign: campaign)
      @logger = logger
    end

    def run(max_pages: nil, urls: nil)
      stats = { pages: 0, created: 0, seen: 0, skipped: 0, dropped: 0, cursors: [] }
      Array(urls || @campaign.historical_urls).each do |start_url|
        break if max_pages && stats[:pages] >= max_pages

        cursor = KyujinboxBackfillCursor.find_or_create_by!(start_url: start_url)
        next if cursor.finished?

        read_until_pause(cursor, max_pages, stats)
        stats[:cursors] << {
          start_url: start_url,
          pages_read: cursor.pages_read,
          stopped: cursor.stop_reason,
          next_url: cursor.next_url
        }
      end
      @logger.info(
        "[KyujinboxBackfill] campaign=#{@campaign.key} pages=#{stats[:pages]} created=#{stats[:created]} " \
        "seen=#{stats[:seen]} skipped=#{stats[:skipped]} dropped=#{stats[:dropped]}"
      )
      stats
    end

    private

    def read_until_pause(cursor, max_pages, stats)
      url = cursor.next_url.presence || cursor.start_url
      loop do
        break if max_pages && stats[:pages] >= max_pages

        result = @importer.crawl_budget(url, max_pages: 1, stats: stats)
        finished = result[:stopped] == "last_page"
        cursor.update!(
          next_url: finished ? nil : result[:next_url],
          pages_read: cursor.pages_read + result[:pages],
          finished: finished,
          stop_reason: max_pages && stats[:pages] >= max_pages && result[:stopped] == "page_limit" ? "page_limit" : result[:stopped]
        )
        break unless result[:stopped] == "page_limit"
        break if max_pages && stats[:pages] >= max_pages

        @importer.sleep(@page_interval) if @page_interval.to_f.positive?
        url = result[:next_url]
      end
    end
  end
end
