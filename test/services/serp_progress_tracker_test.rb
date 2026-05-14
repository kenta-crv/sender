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
  ensure
    SerpProgressTracker.define_method(:write, original_write)
    SerpProgressTracker.send(:protected, :write)
  end

  test "eta is conservative for five item runs" do
    tracker = SerpProgressTracker.new("eta-test")
    numbers = {
      total: 5,
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
