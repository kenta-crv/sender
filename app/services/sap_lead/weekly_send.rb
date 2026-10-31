module SapLead
  class WeeklySend
    def initialize(queue: PlanPriorityQueue, config: SapPipeline, logger: Rails.logger)
      @queue = queue
      @config = config
      @logger = logger
    end

    def run
      admin_id = @config.admin_id
      submission_id = @config.submission_id
      if admin_id.blank? || submission_id.blank?
        @logger.error("[SapWeeklySend] admin_id または submission_id が未設定のため送信しません")
        return nil
      end
      unless Admin.exists?(admin_id) && Submission.exists?(submission_id)
        @logger.error("[SapWeeklySend] 管理者または文面が見つからないため送信しません")
        return nil
      end

      ids = target_ids(admin_id)
      if ids.empty?
        @logger.info("[SapWeeklySend] 送信対象なし")
        return nil
      end

      batch = FormSubmissionBatch.create!(
        total_count: ids.size,
        customer_ids: ids.to_json,
        status: "processing",
        started_at: Time.current,
        error_log: "[]",
        submission_id: submission_id,
        client_id: nil,
        admin_id: admin_id,
        ignore_forbidden_text: true
      )
      @queue.enqueue_form_send_batch(batch.id, client: nil, admin: true)
      batch
    end

    def target_ids(admin_id)
      recent_success_ids = Call.form_submissions
        .where(status: "自動送信成功")
        .where("calls.created_at >= ?", 30.days.ago)
        .select(:customer_id)

      Customer.with_business(Kyujinbox::INDUSTRY)
        .with_real_contact_url
        .visible_on_form_send_list
        .deliverable_for(nil, admin_id)
        .where.not(id: recent_success_ids)
        .pluck(:id)
    end
  end
end
