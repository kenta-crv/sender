module SapLead
  class SundayFollowUp
    def initialize(pipeline: BrightData::Pipeline, queue: PlanPriorityQueue, logger: Rails.logger)
      @pipeline = pipeline
      @queue = queue
      @logger = logger
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
      @pipeline.execute_from_db(customer_ids: ids, limit: ids.size)
      filled_ids = Customer.where(id: ids).select { |customer| before[customer.id].blank? && customer.url.present? }.map(&:id)
      return if filled_ids.empty?

      JobPosting.where(customer_id: filled_ids, official_url: [nil, ""]).update_all(serp_filled_at: Time.current)
    end

    def serp_customer_ids
      customer_ids = JobPosting.where(status: "registered", official_url: [nil, ""])
        .where.not(customer_id: nil)
        .distinct
        .pluck(:customer_id)
      Customer.with_business(Kyujinbox::INDUSTRY).where(id: customer_ids, url: [nil, ""]).pluck(:id)
    end

    def enqueue_contact_detection
      rows = Customer.with_business(Kyujinbox::INDUSTRY)
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
        admin_id: SapPipeline.admin_id,
        sap_pipeline: true
      )
      @queue.enqueue_contact_detect_batch(batch.id, client: nil, admin: true)
      @logger.info("[SapSundayFollowUp] フォーム検出 #{ids.size}件 batch=#{batch.id}")
      batch
    end
  end
end
