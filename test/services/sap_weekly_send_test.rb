require "test_helper"

class SapWeeklySendTest < ActiveSupport::TestCase
  setup do
    @admin = Admin.create!(email: "sap-send-#{SecureRandom.hex(4)}@example.com", password: "password123")
    @submission = Submission.create!(title: "SAP文面", content: "本文", url: "https://example.com/sap")
    @queue = RecordingQueue.new
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
