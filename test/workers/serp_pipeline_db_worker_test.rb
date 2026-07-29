require "test_helper"

class SerpPipelineDbWorkerTest < ActiveSupport::TestCase
  test "perform uses db pipeline without legacy contact detector" do
    customer = Customer.create!(company: "Logistics Pipeline Target")
    captured = nil

    with_singleton_method(BrightData::Pipeline, :execute_from_db, ->(**kwargs) { captured = kwargs }) do
      SerpPipelineDbWorker.new.perform("Logistics", [customer.id], nil, 0)
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

  test "perform stops chaining when pipeline requests stop_chaining" do
    customers = 3.times.map { |i| Customer.create!(company: "Stop Chain #{i}") }
    ids = customers.map(&:id)
    run = SerpEnrichmentRun.create_for_targets!(
      run_id: "stop-chain-run",
      industry: "",
      limit: ids.size,
      targets: customers
    )

    enqueued = []
    worker = SerpPipelineDbWorker.new
    worker.define_singleton_method(:jid) { "jid-stop-1" }

    with_sidekiq_enqueue_stub(enqueued) do
      with_singleton_method(BrightData::Pipeline, :execute_from_db, ->(**_kwargs) { { stop_chaining: true } }) do
        stub_const(SerpPipelineDbWorker, :BATCH_SIZE, 2) do
          worker.perform("", ids, run.run_id, 0)
        end
      end
    end

    assert_equal 0, enqueued.size
  end

  test "perform re-enqueues same offset on Sidekiq::Shutdown without failing run" do
    customers = 3.times.map { |i| Customer.create!(company: "Shutdown Target #{i}") }
    ids = customers.map(&:id)
    run = SerpEnrichmentRun.create_for_targets!(
      run_id: "shutdown-resume-run",
      industry: "",
      limit: ids.size,
      targets: customers
    )

    enqueued = []
    worker = SerpPipelineDbWorker.new
    worker.define_singleton_method(:jid) { "jid-shutdown-1" }

    with_sidekiq_enqueue_stub(enqueued) do
      with_singleton_method(BrightData::Pipeline, :execute_from_db, ->(**_kwargs) { raise Sidekiq::Shutdown }) do
        stub_const(SerpPipelineDbWorker, :BATCH_SIZE, 2) do
          assert_raises(Sidekiq::Shutdown) { worker.perform("", ids, run.run_id, 0) }
        end
      end
    end

    assert_equal 1, enqueued.size
    assert_equal ["", nil, "shutdown-resume-run", 0, "serp_enrichment_admin"], enqueued.first
    refute_equal "error", run.reload.status
    customers.first(2).each do |c|
      assert_nil c.reload.serp_status, "shutdown 後は未完了を未処理へ戻す"
    end
  end

  test "perform reopens Sidekiq::Shutdown failed run and restores incomplete statuses" do
    customers = 2.times.map { |i| Customer.create!(company: "Reopen Target #{i}", serp_status: "serp_error") }
    ids = customers.map(&:id)
    run = SerpEnrichmentRun.create_for_targets!(
      run_id: "reopen-shutdown-run",
      industry: "",
      limit: ids.size,
      targets: customers
    )
    run.update!(status: "error", error_message: "Sidekiq::Shutdown", finished_at: Time.current)

    captured = nil
    worker = SerpPipelineDbWorker.new
    worker.define_singleton_method(:jid) { "jid-reopen-1" }

    with_singleton_method(BrightData::Pipeline, :execute_from_db, ->(**kwargs) { captured = kwargs; { targets: 0 } }) do
      worker.perform("", ids, run.run_id, 0)
    end

    assert_equal "running", run.reload.status
    assert_nil run.error_message
    customers.each { |c| assert_nil c.reload.serp_status }
    assert_equal ids, captured[:customer_ids]
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
