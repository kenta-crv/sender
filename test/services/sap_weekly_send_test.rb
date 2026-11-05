require "test_helper"

class SapWeeklySendTest < ActiveSupport::TestCase
  setup do
    @saved_send_ids = {
      "SAP_SEND_ADMIN_ID" => ENV.delete("SAP_SEND_ADMIN_ID"),
      "SAP_SEND_SUBMISSION_ID" => ENV.delete("SAP_SEND_SUBMISSION_ID")
    }
    @admin = Admin.create!(email: "sap-send-#{SecureRandom.hex(4)}@example.com", password: "password123")
    @submission = Submission.create!(title: "SAP文面", content: "本文", url: "https://example.com/sap")
    @queue = RecordingQueue.new
  end

  teardown do
    @saved_send_ids.each { |key, value| ENV[key] = value if value }
  end

  test "page sales ban is skipped only when the batch flag is on" do
    flagged = FormSender.new(ignore_forbidden_text: true)
    flagged.define_singleton_method(:page_has_no_sales_warning?) { true }
    normal = FormSender.new(ignore_forbidden_text: false)
    normal.define_singleton_method(:page_has_no_sales_warning?) { true }

    refute flagged.send(:sales_text_blocks_send?)
    assert normal.send(:sales_text_blocks_send?)
  end

  test "creates an admin batch that ignores page sales text and skips recent successes" do
    ready = Customer.create!(company: "送信対象株式会社", business: "SAP", contact_url: "https://ready.example/contact", url: "https://ready.example")
    Customer.create!(company: "直近成功株式会社", business: "SAP", contact_url: "https://done.example/contact", url: "https://done.example").tap do |customer|
      Call.create!(customer: customer, call_type: "form", status: "自動送信成功", created_at: 1.day.ago)
    end
    Customer.create!(company: "禁止株式会社", business: "SAP", contact_url: "https://ban.example/contact", url: "https://ban.example", fobbiden: "true")

    config = Struct.new(:admin_id, :submission_id).new(@admin.id, @submission.id)
    batch = SapLead::WeeklySend.new(queue: @queue, config: config).run

    assert_equal [ready.id], JSON.parse(batch.customer_ids)
    assert batch.ignore_forbidden_text
    assert_equal @admin.id, batch.admin_id
    assert_nil batch.client_id
    assert_equal [[batch.id, true]], @queue.form_batches
  end

  test "excludes a company that has a form CAPTCHA NG call" do
    ready = Customer.create!(company: "送信可株式会社", business: "SAP", contact_url: "https://ok.example/contact", url: "https://ok.example")
    blocked = Customer.create!(company: "画像認証株式会社", business: "SAP", contact_url: "https://captcha.example/contact", url: "https://captcha.example")
    Call.create!(customer: blocked, call_type: "form", status: "自動送信失敗")
    Call.create!(customer: blocked, call_type: "form", status: "CAPTCHA NG")

    config = Struct.new(:admin_id, :submission_id).new(@admin.id, @submission.id)
    batch = SapLead::WeeklySend.new(queue: @queue, config: config).run

    assert_equal [ready.id], JSON.parse(batch.customer_ids)
  end

  test "sends to a client owned company as well as a shared company" do
    client = Client.create!(email: "sap-send-owned-#{SecureRandom.hex(4)}@example.com", password: "password123")
    shared = Customer.create!(company: "共有送信株式会社", business: "SAP", contact_url: "https://shared-send.example/contact", url: "https://shared-send.example")
    owned = Customer.create!(
      company: "所有送信株式会社",
      business: "SAP",
      contact_url: "https://owned-send.example/contact",
      url: "https://owned-send.example",
      client: client
    )

    config = Struct.new(:admin_id, :submission_id).new(@admin.id, @submission.id)
    batch = SapLead::WeeklySend.new(queue: @queue, config: config).run

    assert_equal [shared.id, owned.id].sort, JSON.parse(batch.customer_ids).sort
  end

  test "sunday follow up includes client owned companies" do
    client = Client.create!(email: "sap-sunday-owned-#{SecureRandom.hex(4)}@example.com", password: "password123")
    owned_blank = Customer.create!(company: "所有URLなし株式会社", business: "SAP", url: nil, contact_url: nil, client: client)
    JobPosting.create!(
      source: "kyujinbox",
      company_raw: "所有URLなし株式会社",
      company_clean: "所有URLなし",
      title: "SAP担当",
      job_key: "jbn:sunday-owned-#{SecureRandom.hex(4)}",
      status: "registered",
      official_url: nil,
      customer_id: owned_blank.id,
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
    owned_known = Customer.create!(company: "所有URLあり株式会社", business: "SAP", url: "https://owned-known.example", contact_url: nil, client: client)
    shared = Customer.create!(company: "共有URLあり株式会社", business: "SAP", url: "https://shared-known.example", contact_url: nil)
    pipeline = Class.new do
      attr_reader :ids

      def initialize
        @ids = []
      end

      def execute_from_db(customer_ids:, **)
        @ids = customer_ids
      end
    end.new

    SapLead::SundayFollowUp.new(pipeline: pipeline, queue: @queue).run

    assert_equal [owned_blank.id], pipeline.ids
    batch = FormDetectionBatch.find(@queue.detect_batches.first.first)
    assert_equal [owned_known.id, shared.id].sort, JSON.parse(batch.customer_ids).sort
  end

  test "monday send skips a blocked contact url until a new one is found" do
    ready = Customer.create!(company: "送信可株式会社", business: "SAP", contact_url: "https://ok.example/contact", url: "https://ok.example")
    blocked = Customer.create!(
      company: "ハローワーク問い合わせ株式会社",
      business: "SAP",
      contact_url: "https://jinzai.hellowork.mhlw.go.jp/jobs/1",
      url: "https://hw.example"
    )

    config = Struct.new(:admin_id, :submission_id).new(@admin.id, @submission.id)
    batch = SapLead::WeeklySend.new(queue: @queue, config: config).run
    assert_equal [ready.id], JSON.parse(batch.customer_ids)

    blocked.update!(contact_url: "https://hw.example/contact")
    next_batch = SapLead::WeeklySend.new(queue: @queue, config: config).run
    assert_equal [ready.id, blocked.id].sort, JSON.parse(next_batch.customer_ids).sort
  end

  test "sunday detection includes a company whose contact url is blocked" do
    blocked = Customer.create!(
      company: "検出対象株式会社",
      business: "SAP",
      url: "https://detect.example",
      contact_url: "https://jinzai.hellowork.mhlw.go.jp/jobs/2"
    )
    Customer.create!(
      company: "検出不要株式会社",
      business: "SAP",
      url: "https://skip.example",
      contact_url: "https://skip.example/contact"
    )
    pipeline = Class.new do
      def execute_from_db(**)
      end
    end.new

    SapLead::SundayFollowUp.new(pipeline: pipeline, queue: @queue).run

    batch = FormDetectionBatch.find(@queue.detect_batches.first.first)
    assert_equal [blocked.id], JSON.parse(batch.customer_ids)
  end

  test "detection searches again when the saved contact url is blocked and keeps it if none is found" do
    customer = Customer.create!(
      company: "再検出株式会社",
      business: "SAP",
      url: "https://research.example",
      contact_url: "https://jinzai.hellowork.mhlw.go.jp/jobs/3"
    )
    detector = Object.new
    detector.define_singleton_method(:detect) { |*| { status: "not_detected", contact_url: nil, message: "見つかりません" } }
    detector.define_singleton_method(:teardown_driver) {}
    ContactUrlDetector.define_singleton_method(:new) { |*| detector }
    begin
      ContactUrlDetectJob.perform_now(customer.id)
    ensure
      ContactUrlDetector.singleton_class.send(:remove_method, :new)
    end

    customer.reload
    assert_equal "https://jinzai.hellowork.mhlw.go.jp/jobs/3", customer.contact_url
    assert_equal "not_detected", customer.contact_detection_status
  end

  test "does not send when the yml ids are blank" do
    Customer.create!(company: "対象株式会社", business: "SAP", contact_url: "https://ready.example/contact")

    config = Struct.new(:admin_id, :submission_id).new(nil, nil)
    assert_nil SapLead::WeeklySend.new(queue: @queue, config: config).run
    assert_empty @queue.form_batches
  end

  test "sunday serp fills a blank url then queues contact detection" do
    customer = Customer.create!(company: "URLなし株式会社", business: "SAP", url: nil, contact_url: nil)
    posting = JobPosting.create!(
      source: "kyujinbox",
      company_raw: "URLなし株式会社",
      company_clean: "URLなし",
      title: "SAP担当",
      job_key: "jbn:sunday-#{SecureRandom.hex(4)}",
      status: "registered",
      official_url: nil,
      customer_id: customer.id,
      first_seen_at: Time.current,
      last_seen_at: Time.current
    )
    known = Customer.create!(company: "URLあり株式会社", business: "SAP", url: "https://known.example", contact_url: nil)
    pipeline = Class.new do
      def execute_from_db(customer_ids:, **)
        Customer.where(id: customer_ids).update_all(url: "https://serp.example")
      end
    end.new

    SapLead::SundayFollowUp.new(pipeline: pipeline, queue: @queue).run

    assert posting.reload.serp_filled_at.present?
    assert_equal "https://serp.example", customer.reload.url
    batch = FormDetectionBatch.find(@queue.detect_batches.first.first)
    assert batch.sap_pipeline
    assert_includes JSON.parse(batch.customer_ids), known.id
    assert_includes JSON.parse(batch.customer_ids), customer.id
  end

  class RecordingQueue
    attr_reader :form_batches, :detect_batches

    def initialize
      @form_batches = []
      @detect_batches = []
    end

    def enqueue_form_send_batch(batch_id, client:, admin:)
      @form_batches << [batch_id, admin]
    end

    def enqueue_contact_detect_batch(batch_id, client:, admin:)
      @detect_batches << [batch_id, admin]
    end
  end
end
