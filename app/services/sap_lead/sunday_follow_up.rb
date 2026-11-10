module SapLead
  class SundayFollowUp
    SERP_INTERVAL = 15
    SERP_ERROR_RETRY_AFTER = 7.days

    def initialize(pipeline: BrightData::Pipeline, queue: PlanPriorityQueue, logger: Rails.logger, campaign: nil)
      @pipeline = pipeline
      @queue = queue
      @logger = logger
      @campaign = campaign || Pipeline::Campaign.sap
    end

    def run
      fill_missing_urls
      enqueue_contact_detection
    end

    private

    def fill_missing_urls
      ids = serp_customer_ids
      return if ids.empty?

      before = Customer.where(id: ids).pluck(:id, :url).to_h
      @pipeline.execute_from_db(
        customer_ids: ids,
        limit: ids.size,
        delay_between: SERP_INTERVAL,
        retry_serp_error_after: SERP_ERROR_RETRY_AFTER
      )
      filled_ids = Customer.where(id: ids).select { |customer| before[customer.id].blank? && customer.url.present? }.map(&:id)
      return if filled_ids.empty?

      JobPosting.where(customer_id: filled_ids, official_url: [nil, ""]).update_all(serp_filled_at: Time.current)
    end

    def serp_customer_ids
      customer_ids = campaign_postings.where.not(customer_id: nil).distinct.pluck(:customer_id)
      ids = Customer.with_business(@campaign.business).where(id: customer_ids, url: [nil, ""]).order(:id).pluck(:id)
      limit = @campaign.serp_daily_limit
      limit ? ids.first(limit) : ids
    end

    def campaign_postings
      scope = JobPosting.where(status: "registered", official_url: [nil, ""])
      if @campaign.sap?
        scope.where("campaign_key IS NULL OR campaign_key = ?", "sap")
      else
        scope.where(campaign_key: @campaign.key)
      end
    end

    def enqueue_contact_detection
      rows = Customer.with_business(@campaign.business)
        .where.not(url: [nil, ""])
        .pluck(:id, :contact_url)
      ids = rows.select { |_, contact_url| contact_url.blank? || Customer.blocked_url?(contact_url) }.map(&:first)
      if ids.empty?
        @logger.info("[SapSundayFollowUp] フォーム検出の対象なし")
        return nil
      end

      batch = FormDetectionBatch.create!(
        total_count: ids.size,
        customer_ids: ids.to_json,
        status: "processing",
        started_at: Time.current,
        admin_id: @campaign.admin_id,
        sap_pipeline: @campaign.sap?
      )
      @queue.enqueue_contact_detect_batch(batch.id, client: nil, admin: true)
      @logger.info("[SapSundayFollowUp] フォーム検出 #{ids.size}件 batch=#{batch.id}")
      batch
    end
  end
end
