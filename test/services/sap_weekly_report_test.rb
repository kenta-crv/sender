require "test_helper"

class SapWeeklyReportTest < ActiveSupport::TestCase
  FRIDAY = Time.zone.local(2026, 10, 30, 21, 43)

  test "appends one row for the previous Saturday through Friday" do
    from = Time.zone.local(2026, 10, 24, 3, 0)
    inside = Time.zone.local(2026, 10, 27, 12, 0)
    customer = Customer.create!(company: "レポート株式会社", business: "SAP")
    other = Customer.create!(company: "他業種株式会社", business: "製造")
    admin = Admin.create!(email: "sap-report-#{SecureRandom.hex(4)}@example.com", password: "password123")
    posting(job_key: "jbn:report-seen", last_seen_at: inside, first_seen_at: from - 10.days)
    posting(job_key: "jbn:report-new", last_seen_at: inside, first_seen_at: inside)
    posting(job_key: "jbn:report-skip", status: "skipped", skip_reason: "30日以内に処理済み", first_seen_at: inside, last_seen_at: inside)
    posting(job_key: "jbn:report-none", status: "skipped", skip_reason: "法人番号なし", classified_at: inside, first_seen_at: from - 10.days, last_seen_at: from - 10.days)
    posting(job_key: "jbn:report-dup", status: "skipped", skip_reason: "同名複数", classified_at: inside, first_seen_at: from - 10.days, last_seen_at: from - 10.days)
    posting(job_key: "jbn:report-created", status: "registered", registration_kind: "created", registered_at: inside, classified_at: inside, official_url: "https://created.example", customer: customer)
    posting(job_key: "jbn:report-appended", status: "registered", registration_kind: "appended", registered_at: inside, customer: customer)
    posting(job_key: "jbn:report-serp", status: "registered", serp_filled_at: inside, customer: customer)
    posting(job_key: "jbn:report-old", last_seen_at: from - 10.days, first_seen_at: from - 10.days)
    posting(job_key: "jbn:report-unrelated", status: "skipped", skip_reason: "SAP関連外", first_seen_at: inside, last_seen_at: from - 10.days)

    FormDetectionBatch.create!(total_count: 3, customer_ids: [customer.id].to_json, status: "completed", started_at: inside, sap_pipeline: true, success_count: 2, failure_count: 1)
    batch = FormSubmissionBatch.create!(
      total_count: 1,
      processed_count: 5,
      customer_ids: [customer.id].to_json,
      status: "completed",
      started_at: inside,
      completed_at: inside + 1.hour,
      ignore_forbidden_text: true,
      error_log: "[]"
    )
    %w[自動送信成功 自動送信失敗 CAPTCHA\ NG 営業禁止 差し込みエラー].each do |status|
      Call.create!(customer: customer, call_type: "form", status: status, created_at: inside + 10.minutes)
    end
    DeliveryOptOut.create!(customer: customer, admin: admin, created_at: inside)
    DeliveryOptOut.create!(customer: other, admin: admin, created_at: inside)
    link = ClickTrackingLink.create!(customer: customer, form_submission_batch: batch, target_url: "https://example.com/detail")
    ClickLog.create!(click_tracking_link: link, created_at: inside)

    sheet = FakeSheet.new([])
    result = SapLead::WeeklyReport.new(sheets: sheet, now: FRIDAY).run

    assert_equal :appended, result
    row = sheet.appended.first
    assert_equal "2026-10-24", row[0]
    assert_equal "2026-10-30", row[1]
    assert_equal 3, row[2]
    assert_equal 3, row[3]
    assert_equal 1, row[4]
    assert_equal 1, row[5]
    assert_equal 1, row[6]
    assert_equal 1, row[7]
    assert_equal 1, row[8]
    assert_equal 1, row[9]
    assert_equal 1, row[10]
    assert_equal 2, row[11]
    assert_equal 1, row[12]
    assert_equal 5, row[13]
    assert_equal [1, 1, 1, 1, 1], row[14..18]
    assert_equal 1, row[19]
    assert_equal 1, row[20]
    assert_equal ["", "", "", ""], row[21..24]
    assert_equal 1, row[25]
  end

  test "does nothing when the week is already on the sheet" do
    sheet = FakeSheet.new(["2026-10-24"])
    result = SapLead::WeeklyReport.new(sheets: sheet, now: FRIDAY).run

    assert_equal :skipped, result
    assert_empty sheet.appended
    assert_equal 0, Notification.where(type: "SapWeeklyReport").count
  end

  test "records a notification when the sheet write fails" do
    sheet = FakeSheet.new([])
    def sheet.append_unless_present(*)
      raise "sheets down"
    end

    assert_nil SapLead::WeeklyReport.new(sheets: sheet, now: FRIDAY).run
    notice = Notification.where(type: "SapWeeklyReport", status: "error").last
    assert_match "sheets down", notice.message
    assert_nil notice.client_id
  end

  test "google sheet skips a duplicate start date before appending" do
    service = FakeSheetService.new(title: "Untitled", column_a: ["週開始日", "2026-10-24"])
    result = SapLead::GoogleSheet.new(service: service).append_unless_present("sheet-id", ["2026-10-24", "2026-10-30"])

    assert_equal :skipped, result
    assert_empty service.appended
  end

  private

  def posting(job_key:, **attrs)
    JobPosting.create!({
      source: "kyujinbox",
      company_raw: "レポート株式会社",
      company_clean: "レポート",
      title: "SAP担当",
      job_key: job_key,
      status: "new"
    }.merge(attrs))
  end

  class FakeSheet
    attr_reader :appended

    def initialize(existing)
      @existing = existing
      @appended = []
    end

    def append_unless_present(_spreadsheet_id, row)
      return :skipped if @existing.include?(row.first)

      @appended << row
      :appended
    end
  end

  class FakeSheetService
    attr_reader :appended

    def initialize(title:, column_a:)
      @title = title
      @column_a = column_a
      @appended = []
    end

    def sheet_title(_spreadsheet_id)
      @title
    end

    def column_a(_spreadsheet_id, _title)
      @column_a
    end

    def append(_spreadsheet_id, _title, row)
      @appended << row
    end
  end
end
