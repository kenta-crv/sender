require "test_helper"

class SerpProgressTrackerTest < ActiveSupport::TestCase
  test "start initializes queued payload without calling protected writer externally" do
    writes = []
    original_write = SerpProgressTracker.instance_method(:write)

    SerpProgressTracker.define_method(:write) do |attributes|
      writes << attributes
    end

    SerpProgressTracker.start(
      run_id: "abc123",
      total: 2,
      industry: "軽貨物",
      target_ids: [10, 20]
    )

    assert_equal 1, writes.size
    assert_equal "abc123", writes.first[:run_id]
    assert_equal "queued", writes.first[:phase]
    assert_equal 2, writes.first[:total]
    assert_equal 2, writes.first[:target_count]
    assert_equal 2, writes.first[:target_total]
    assert_equal 0, writes.first[:target_completed]
    assert_equal "10,20", writes.first[:target_ids]
    assert_equal [], JSON.parse(writes.first[:target_preview])
  ensure
    SerpProgressTracker.define_method(:write, original_write)
    SerpProgressTracker.send(:protected, :write)
  end

  test "finish marks target based progress as completed" do
    writes = []
    original_write = SerpProgressTracker.instance_method(:write)
    original_read = SerpProgressTracker.instance_method(:read)

    SerpProgressTracker.define_method(:write) do |attributes|
      writes << attributes
    end
    SerpProgressTracker.define_method(:read) do
      {
        "total" => "3",
        "target_total" => "3",
        "target_completed" => "1",
        "serp_total" => "3",
        "web_total" => "3"
      }
    end

    SerpProgressTracker.new("finish-test").finish(done_count: 3, error_count: 0)

    assert_equal "done", writes.last[:phase]
    assert_equal 3, writes.last[:target_total]
    assert_equal 3, writes.last[:target_completed]
    assert_equal 3, writes.last[:web_completed]
  ensure
    SerpProgressTracker.define_method(:write, original_write)
    SerpProgressTracker.define_method(:read, original_read)
    SerpProgressTracker.send(:protected, :write, :read)
  end

  test "payload refreshes target preview status from current customer state" do
    customer = Customer.create!(company: "Preview Refresh Target", serp_status: nil)
    original_read = SerpProgressTracker.instance_method(:read)

    SerpProgressTracker.define_method(:read) do
      {
        "run_id" => "preview-refresh",
        "phase" => "done",
        "total" => "1",
        "target_total" => "1",
        "target_completed" => "1",
        "target_ids" => customer.id.to_s,
        "target_preview" => JSON.generate([
          {
            id: customer.id,
            company: customer.company,
            serp_status: "",
            serp_status_label: "未処理"
          }
        ]),
        "target_preview_limit" => "20",
        "serp_total" => "1",
        "serp_completed" => "1",
        "web_total" => "1",
        "web_completed" => "1",
        "done_count" => "1",
        "error_count" => "0",
        "message" => "done",
        "started_at" => Time.current.iso8601,
        "updated_at" => Time.current.iso8601
      }
    end

    customer.update!(serp_status: "serp_done")

    preview = SerpProgressTracker.payload("preview-refresh")[:target_preview]
    assert_equal "serp_done", preview.first[:serp_status]
    assert_equal "完了", preview.first[:serp_status_label]
  ensure
    SerpProgressTracker.define_method(:read, original_read)
    SerpProgressTracker.send(:protected, :read)
  end

  test "payload treats blank serp status with tel or url as done" do
    customer = Customer.create!(company: "Preview Effective Done Target", serp_status: nil, tel: "03-1111-1111")
    original_read = SerpProgressTracker.instance_method(:read)

    SerpProgressTracker.define_method(:read) do
      {
        "run_id" => "preview-effective-done",
        "phase" => "done",
        "total" => "1",
        "target_total" => "1",
        "target_completed" => "1",
        "target_ids" => customer.id.to_s,
        "target_preview" => "[]",
        "target_preview_limit" => "20",
        "serp_total" => "1",
        "serp_completed" => "1",
        "web_total" => "1",
        "web_completed" => "1",
        "done_count" => "1",
        "error_count" => "0",
        "message" => "done",
        "started_at" => Time.current.iso8601,
        "updated_at" => Time.current.iso8601
      }
    end

    preview = SerpProgressTracker.payload("preview-effective-done")[:target_preview]

    assert_equal "serp_done", preview.first[:serp_status]
  ensure
    SerpProgressTracker.define_method(:read, original_read)
    SerpProgressTracker.send(:protected, :read)
  end

  test "payload includes audit run identifiers and before after target preview" do
    customer = Customer.create!(company: "Audit Preview Target", serp_status: nil)
    run = SerpEnrichmentRun.create_for_targets!(
      run_id: "audit-preview",
      industry: "",
      limit: 1,
      targets: [customer]
    )
    started_at = 5.minutes.ago
    finished_at = Time.current
    run.update!(jid: "jid-preview", status: "done", started_at: started_at, finished_at: finished_at)
    customer.update!(serp_status: "serp_done", url: "https://preview.example/")
    run.targets.first.refresh_after!(
      customer: customer,
      result_status: "updated",
      candidate_count: 2,
      selected_url: customer.url,
      update_keys: ["url"]
    )

    original_read = SerpProgressTracker.instance_method(:read)
    SerpProgressTracker.define_method(:read) do
      {
        "run_id" => "audit-preview",
        "phase" => "web",
        "total" => "1",
        "target_total" => "1",
        "target_completed" => "0",
        "target_ids" => customer.id.to_s,
        "target_preview" => "[]",
        "target_preview_limit" => "20",
        "serp_total" => "1",
        "serp_completed" => "1",
        "web_total" => "1",
        "web_completed" => "0",
        "done_count" => "0",
        "error_count" => "0",
        "message" => "running",
        "started_at" => 10.minutes.ago.iso8601,
        "updated_at" => Time.current.iso8601
      }
    end

    payload = SerpProgressTracker.payload("audit-preview")
    assert_equal "audit-preview", payload[:run_id]
    assert_equal "jid-preview", payload[:jid]
    assert_equal "done", payload[:run_status]
    assert_equal false, payload[:active]
    assert_equal 100.0, payload[:percent]
    assert_equal SerpProgressTracker.format_duration(finished_at - started_at), payload[:elapsed_label]
    assert_equal "serp_done", payload[:target_preview].first[:serp_status]
    assert_equal "https://preview.example/", payload[:target_preview].first[:hp_url]
    assert_equal "", payload[:target_preview].first[:before_serp_status]
    assert_equal "updated", payload[:target_preview].first[:result_status]
    assert_equal ["url"], payload[:target_preview].first[:update_keys]
  ensure
    SerpProgressTracker.define_method(:read, original_read) if original_read
    SerpProgressTracker.send(:protected, :read)
  end

  test "eta is conservative for five item runs" do
    tracker = SerpProgressTracker.new("eta-test")
    numbers = {
      total: 5,
      target_total: 5,
      target_completed: 0,
      serp_total: 5,
      serp_completed: 5,
      web_total: 5,
      web_completed: 0,
      done_count: 0,
      error_count: 0
    }

    assert_equal "3分", tracker.send(:estimate_label, 60, 45.0, true, numbers: numbers, phase: "web")
  end

  test "eta rounds remaining time up while elapsed remains floor based" do
    assert_equal "1分", SerpProgressTracker.format_duration(119)
    assert_equal "2分", SerpProgressTracker.format_duration(61, round_up: true)
  end

  test "eta labels completed and unmeasured states" do
    tracker = SerpProgressTracker.new("eta-test")
    numbers = {
      total: 5,
      target_total: 5,
      target_completed: 0,
      serp_total: 5,
      serp_completed: 0,
      web_total: 0,
      web_completed: 0,
      done_count: 0,
      error_count: 0
    }

    assert_equal "完了", tracker.send(:estimate_label, 180, 100.0, false, numbers: numbers, phase: "done")
    assert_equal "計測中", tracker.send(:estimate_label, 0, 0.0, true, numbers: numbers, phase: "queued")
  end
end
