module SapLead
  class WeeklyReport
    def initialize(webhook: nil, logger: Rails.logger, now: Time.zone.now)
      @webhook = webhook
      @logger = logger
      @now = now
    end

    def run
      row = build_row(@now)
      result = (@webhook || ReportWebhook.new).append_row(row)
      @logger.info("[SapWeeklyReport] #{result} #{row.first}")
      result
    rescue StandardError => e
      @logger.error("[SapWeeklyReport] #{e.class}: #{e.message}")
      Notification.create!(
        type: "SapWeeklyReport",
        status: "error",
        client_id: nil,
        message: "SAP週次レポートの書き込みに失敗しました: #{e.message}"
      )
      nil
    end

    def build_row(now)
      from, to = self.class.period(now)
      batches = FormSubmissionBatch.where(ignore_forbidden_text: true, started_at: from..to)
      detections = FormDetectionBatch.where(sap_pipeline: true, started_at: from..to)
      status_counts = call_status_counts(batches, to)
      sap_customer_ids = Customer.with_business(Kyujinbox::INDUSTRY).select(:id)
      batch_ids = batches.pluck(:id)
      clicks = if batch_ids.empty?
        0
      else
        ClickLog.joins(:click_tracking_link)
          .where(click_tracking_links: { form_submission_batch_id: batch_ids }, created_at: from..to)
          .count
      end

      [
        from.to_date.iso8601,
        to.to_date.iso8601,
        JobPosting.where(last_seen_at: from..to).count,
        JobPosting.where(first_seen_at: from..to).count,
        JobPosting.where(skip_reason: JobPosting::RECENT_SKIP_REASON, first_seen_at: from..to).count,
        JobPosting.where(skip_reason: "法人番号なし", classified_at: from..to).count,
        JobPosting.where(skip_reason: "同名複数", classified_at: from..to).count,
        JobPosting.where(registration_kind: "created", registered_at: from..to).count,
        JobPosting.where(registration_kind: "appended", registered_at: from..to).count,
        JobPosting.where(classified_at: from..to).where.not(official_url: [nil, ""]).count,
        JobPosting.where(serp_filled_at: from..to).count,
        detections.sum(:success_count).to_i,
        detections.sum(:failure_count).to_i,
        batches.sum(:processed_count).to_i,
        status_counts["自動送信成功"].to_i,
        status_counts["自動送信失敗"].to_i,
        status_counts["CAPTCHA NG"].to_i,
        status_counts["営業禁止"].to_i,
        status_counts["差し込みエラー"].to_i,
        DeliveryOptOut.where(customer_id: sap_customer_ids, created_at: from..to).count,
        clicks,
        "",
        "",
        "",
        "",
        JobPosting.where(skip_reason: JobPosting::UNRELATED_SKIP_REASON, first_seen_at: from..to).count
      ]
    end

    def self.period(now)
      friday = now.to_date
      friday -= 1 until friday.friday?
      [(friday - 6).in_time_zone.beginning_of_day, friday.in_time_zone.end_of_day]
    end

    private

    def call_status_counts(batches, period_end)
      counts = Hash.new(0)
      batches.each do |batch|
        window_end = batch.completed_at || period_end
        Call.form_submissions
          .where(customer_id: batch.parsed_customer_ids, created_at: batch.started_at..window_end)
          .group(:status)
          .count
          .each { |status, count| counts[status] += count }
      end
      counts
    end
  end
end
