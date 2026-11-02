module Kyujinbox
  class Importer
    def initialize(client: Kyujinbox::Client.new, page_interval: PAGE_INTERVAL, logger: Rails.logger)
      @client = client
      @page_interval = page_interval
      @logger = logger
      @seen_company_keys = {}
    end

    def run(start_urls: nil, max_pages: nil)
      stats = { pages: 0, created: 0, seen: 0, skipped: 0, dropped: 0 }
      Array(start_urls || Kyujinbox.start_urls).each do |start_url|
        crawl(start_url, max_pages: max_pages, stats: stats)
      end
      @logger.info(
        "[Kyujinbox] 業種=#{INDUSTRY} pages=#{stats[:pages]} created=#{stats[:created]} " \
        "seen=#{stats[:seen]} skipped=#{stats[:skipped]} dropped=#{stats[:dropped]}"
      )
      stats
    end

    private

    def crawl(start_url, max_pages:, stats:)
      url = start_url
      page_no = 0
      while url.present?
        page_no += 1
        break if max_pages && page_no > max_pages

        page = Parser.extract(@client.get(url), page_url: url)
        stats[:pages] += 1
        all_seen = page.postings.any? && page.postings.all? { |posting| JobPosting.exists?(job_key: posting.job_key) }
        page.postings.each { |posting| import_posting(posting, stats) }
        @logger.info("[Kyujinbox] page=#{page_no} url=#{url} postings=#{page.postings.size} next=#{page.next_url.present?}")
        break if all_seen

        url = page.next_url
        sleep @page_interval if url.present? && @page_interval.to_f.positive?
      end
    end

    def import_posting(posting, stats)
      existing = JobPosting.find_by(job_key: posting.job_key)
      if existing
        existing.update_columns(last_seen_at: Time.current, updated_at: Time.current)
        stats[:seen] += 1
        return
      end

      unless Kyujinbox.title_relevant?(posting.title)
        create_posting(posting, status: "skipped", skip_reason: JobPosting::UNRELATED_SKIP_REASON)
        stats[:skipped] += 1
        return
      end

      key = Kyujinbox.company_key(posting.company_clean, posting.posting_url)
      if @seen_company_keys[key]
        stats[:dropped] += 1
        return
      end

      if recent_company?(posting.company_clean)
        create_posting(posting, status: "skipped", skip_reason: JobPosting::RECENT_SKIP_REASON)
        @seen_company_keys[key] = true
        stats[:skipped] += 1
        return
      end

      create_posting(posting, status: "new", skip_reason: nil)
      @seen_company_keys[key] = true
      stats[:created] += 1
    end

    def recent_company?(company_clean)
      return false if company_clean.blank?

      JobPosting.where(company_clean: company_clean)
        .where("last_seen_at >= ?", 30.days.ago)
        .where("skip_reason IS NULL OR skip_reason != ?", JobPosting::UNRELATED_SKIP_REASON)
        .exists?
    end

    def create_posting(posting, status:, skip_reason:)
      now = Time.current
      JobPosting.create!(
        source: "kyujinbox",
        company_raw: posting.company_raw,
        company_clean: posting.company_clean,
        title: posting.title,
        area: posting.area,
        employ_type: posting.employ_type,
        posting_url: posting.posting_url,
        job_key: posting.job_key,
        first_seen_at: now,
        last_seen_at: now,
        status: status,
        skip_reason: skip_reason
      )
    end
  end
end
