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

    webhook = FakeWebhook.new(:appended)
    result = SapLead::WeeklyReport.new(webhook: webhook, now: FRIDAY).run

    assert_equal :appended, result
    row = webhook.rows.first
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

  test "accepts exists when the same week is already on the sheet" do
    webhook = FakeWebhook.new(:exists)
    result = SapLead::WeeklyReport.new(webhook: webhook, now: FRIDAY).run

    assert_equal :exists, result
    assert_nil webhook.sheets.first
    assert_equal "営業代行", webhook.sheets.last
    assert_equal 0, Notification.where(type: "SapWeeklyReport").count
  end

  test "records a notification when the webhook write fails" do
    webhook = FakeWebhook.new(:appended)
    def webhook.append_row(*, **)
      raise "webhook down"
    end

    assert_nil SapLead::WeeklyReport.new(webhook: webhook, now: FRIDAY).run
    notice = Notification.where(type: "SapWeeklyReport", status: "error").last
    assert_match "webhook down", notice.message
    assert_nil notice.client_id
  end

  test "webhook posts the row and reads the result after the redirect" do
    row = ["2026-10-24", "2026-10-30"] + Array.new(24, 0)
    transport = RedirectTransport.new('{"result":"appended"}')
    result = SapLead::ReportWebhook.new(url: "https://script.google.com/macros/s/test/exec", secret: "test-secret", transport: transport).append_row(row)

    assert_equal :appended, result
    assert_equal "POST", transport.calls[0][:method]
    assert_equal "GET", transport.calls[1][:method]
    assert_equal "https://script.googleusercontent.com/macros/echo", transport.calls[1][:url]
    body = JSON.parse(transport.calls[0][:body])
    assert_equal "test-secret", body["secret"]
    assert_equal row, body["row"]
    refute body.key?("sheet")
  end

  test "webhook adds the campaign sheet and keeps the same 26 columns" do
    row = Array.new(26, 0)
    transport = RedirectTransport.new('{"result":"appended"}')
    result = SapLead::ReportWebhook.new(url: "https://script.google.com/macros/s/test/exec", secret: "test-secret", transport: transport).append_row(row, sheet: "営業代行")

    body = JSON.parse(transport.calls[0][:body])
    assert_equal :appended, result
    assert_equal "営業代行", body["sheet"]
    assert_equal row, body["row"]
    assert_equal 26, body["row"].size
  end

  test "webhook treats forbidden as a failure and does not include the secret" do
    row = Array.new(26, "")
    transport = RedirectTransport.new('{"result":"forbidden"}')
    error = assert_raises(RuntimeError) do
      SapLead::ReportWebhook.new(url: "https://script.google.com/macros/s/test/exec", secret: "test-secret", transport: transport).append_row(row)
    end

    assert_match "forbidden", error.message
    assert_no_match "test-secret", error.message
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

  class FakeWebhook
    attr_reader :rows

    def initialize(result)
      @result = result
      @rows = []
      @sheets = []
    end

    attr_reader :sheets

    def append_row(row, sheet: nil)
      @rows << row
      @sheets << sheet
      @result
    end
  end

  class RedirectTransport
    attr_reader :calls

    def initialize(body)
      @body = body
      @calls = []
    end

    def call(request, uri)
      @calls << { method: request.method, url: uri.to_s, body: request.body }
      if @calls.size == 1
        response = Net::HTTPFound.new("1.1", "302", "Found")
        response["Location"] = "https://script.googleusercontent.com/macros/echo"
        response
      else
        response = Net::HTTPOK.new("1.1", "200", "OK")
        response.instance_variable_set(:@body, @body)
        response.instance_variable_set(:@read, true)
        response
      end
    end
  end
end
