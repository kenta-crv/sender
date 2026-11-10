module Kyujinbox
  class Backfill
    MAX_PAGES = 100
    PAGE_INTERVAL = 3

    def initialize(client: Kyujinbox::Client.new, page_interval: PAGE_INTERVAL, logger: Rails.logger)
      @importer = Importer.new(client: client, page_interval: page_interval, logger: logger)
      @logger = logger
    end

    def run(max_pages: MAX_PAGES)
      stats = { pages: 0, created: 0, seen: 0, skipped: 0, dropped: 0, cursors: [] }
      remaining = max_pages
      Kyujinbox.backfill_urls.each do |start_url|
        break if remaining <= 0

        cursor = KyujinboxBackfillCursor.find_or_create_by!(start_url: start_url)
        next if cursor.finished?

        result = @importer.crawl_budget(cursor.next_url.presence || start_url, max_pages: remaining, stats: stats)
        remaining -= result[:pages]
        cursor.update!(
          next_url: result[:next_url],
          pages_read: cursor.pages_read + result[:pages],
          finished: result[:next_url].blank?,
          stop_reason: result[:stopped]
        )
        stats[:cursors] << {
          start_url: start_url,
          pages: result[:pages],
          pages_read: cursor.pages_read,
          stopped: result[:stopped],
          next_url: result[:next_url]
        }
      end
      @logger.info("[KyujinboxBackfill] pages=#{stats[:pages]} created=#{stats[:created]} seen=#{stats[:seen]} skipped=#{stats[:skipped]} dropped=#{stats[:dropped]}")
      stats
    end
  end
end
