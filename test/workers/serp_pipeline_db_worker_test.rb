require "test_helper"

class SerpPipelineDbWorkerTest < ActiveSupport::TestCase
  test "perform uses db pipeline without legacy contact detector" do
    captured = nil

    with_singleton_method(BrightData::Pipeline, :execute_from_db, ->(**kwargs) { captured = kwargs }) do
      SerpPipelineDbWorker.new.perform("Logistics", [], nil, 0)
    end

    assert_equal "Logistics", captured[:industry]
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
      worker.perform("", [customer.id], run.run_id, 0)
    end

    assert_equal "running", run.reload.status
    assert_equal "jid-worker-1", run.jid
    assert_equal "worker-audit-run", captured[:progress_run_id]
    assert_equal "jid-worker-1", captured[:jid]
    assert_equal [customer.id], captured[:customer_ids]
    assert_equal true, captured[:finalize_run]
  end

  test "perform resolves target ids from audit run for chained batches" do
    customers = 3.times.map { |i| Customer.create!(company: "Audit ID Target #{i}") }
    ids = customers.map(&:id)
    run = SerpEnrichmentRun.create_for_targets!(
      run_id: "audit-id-run",
      industry: "Logistics",
      limit: ids.size,
      targets: customers
    )

    captured = nil
    worker = SerpPipelineDbWorker.new
    worker.define_singleton_method(:jid) { "jid-audit-ids" }

    with_singleton_method(BrightData::Pipeline, :execute_from_db, ->(**kwargs) { captured = kwargs }) do
      stub_const(SerpPipelineDbWorker, :BATCH_SIZE, 2) do
        worker.perform(nil, nil, run.run_id, 2)
      end
    end

    assert_equal [customers[2].id], captured[:customer_ids]
    assert_equal "Logistics", captured[:industry]
    assert_equal true, captured[:finalize_run]
  end

  test "perform chains next batch on success and stops on failure" do
    customers = 3.times.map { |i| Customer.create!(company: "Batch Target #{i}") }
    ids = customers.map(&:id)
    run = SerpEnrichmentRun.create_for_targets!(
      run_id: "batch-chain-run",
      industry: "",
      limit: ids.size,
      targets: customers
    )

    enqueued = []
    worker = SerpPipelineDbWorker.new
    worker.define_singleton_method(:jid) { "jid-batch-1" }

    with_sidekiq_enqueue_stub(enqueued) do
      with_singleton_method(BrightData::Pipeline, :execute_from_db, ->(**_kwargs) { true }) do
        stub_const(SerpPipelineDbWorker, :BATCH_SIZE, 2) do
          worker.perform("", ids, run.run_id, 0)
        end
      end
    end

    assert_equal 1, enqueued.size
    assert_equal ["", nil, "batch-chain-run", 2, "serp_enrichment_admin"], enqueued.first

    with_sidekiq_enqueue_stub(enqueued) do
      with_singleton_method(BrightData::Pipeline, :execute_from_db, ->(**_kwargs) { raise "boom" }) do
        stub_const(SerpPipelineDbWorker, :BATCH_SIZE, 2) do
          assert_raises(RuntimeError) { worker.perform("", ids, run.run_id, 2) }
        end
      end
    end

    assert_equal "error", run.reload.status
    assert_equal 1, enqueued.size, "failed batch must not enqueue another job"
  end

  private

  def with_sidekiq_enqueue_stub(enqueued)
    chain_target = Object.new
    chain_target.define_singleton_method(:perform_async) { |*args| enqueued << args }

    with_singleton_method(SerpPipelineDbWorker, :set, ->(**_kwargs) { chain_target }) do
      yield
    end
  end

  def with_singleton_method(klass, method_name, replacement)
    original = klass.method(method_name)
    klass.define_singleton_method(method_name, &replacement)
    yield
  ensure
    klass.define_singleton_method(method_name) do |*args, **kwargs, &block|
      original.call(*args, **kwargs, &block)
    end
  end

  def stub_const(klass, name, value)
    original = klass.const_get(name)
    klass.send(:remove_const, name)
    klass.const_set(name, value)
    yield
  ensure
    klass.send(:remove_const, name)
    klass.const_set(name, original)
  end
end
