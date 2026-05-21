require "test_helper"

class SerpPipelineDbWorkerTest < ActiveSupport::TestCase
  test "perform uses db pipeline without legacy contact detector" do
    captured = nil

    with_singleton_method(BrightData::Pipeline, :execute_from_db, ->(**kwargs) { captured = kwargs }) do
      SerpPipelineDbWorker.new.perform("Logistics", 10)
    end

    assert_equal "Logistics", captured[:industry]
    assert_equal 10, captured[:limit]
    assert_nil captured[:customer_ids]
    assert_nil captured[:progress_run_id]
    assert_equal false, captured[:detect_contact]
    assert_equal false, captured[:dry_run]
  end

  test "perform attaches jid and marks audit run running" do
    customer = Customer.create!(company: "Worker Audit Target")
    run = SerpEnrichmentRun.create_for_targets!(
      run_id: "worker-audit-run",
      industry: "",
      limit: 1,
      targets: [customer]
    )
    captured = nil
    worker = SerpPipelineDbWorker.new
    worker.define_singleton_method(:jid) { "jid-worker-1" }

    with_singleton_method(BrightData::Pipeline, :execute_from_db, ->(**kwargs) { captured = kwargs }) do
      worker.perform("", 1, [customer.id], run.run_id)
    end

    assert_equal "running", run.reload.status
    assert_equal "jid-worker-1", run.jid
    assert_equal "worker-audit-run", captured[:progress_run_id]
    assert_equal "jid-worker-1", captured[:jid]
  end

  private

  def with_singleton_method(klass, method_name, replacement)
    original = klass.method(method_name)
    klass.define_singleton_method(method_name, &replacement)
    yield
  ensure
    klass.define_singleton_method(method_name) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end
end
