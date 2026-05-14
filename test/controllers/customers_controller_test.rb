require "test_helper"

class CustomersControllerTest < ActionDispatch::IntegrationTest
  test "draft filters customers by company query" do
    target = Customer.create!(company: "Draft Company Query Target", status: "draft")
    other = Customer.create!(company: "Draft Company Query Other", status: "draft")

    get draft_customers_path, params: { company_query: "Query Target" }

    assert_response :success
    assert_includes @response.body, target.company
    refute_includes @response.body, other.company
  end

  test "serp_search does not fall back to synchronous pipeline when sidekiq is unavailable" do
    Customer.create!(company: "SERP Sidekiq Guard Test", status: "draft")

    unavailable = SerpSidekiqManager::Result.new(
      ready: false,
      started: false,
      message: "Redisに接続できないため、SERP補完を開始できませんでした。"
    )

    with_singleton_method(SerpSidekiqManager, :ensure_running, ->(*_args, **_kwargs) { unavailable }) do
      with_singleton_method(BrightData::Pipeline, :execute_from_db, ->(*_args, **_kwargs) { flunk "UI should not run the SERP pipeline synchronously" }) do
        with_singleton_method(SerpPipelineDbWorker, :perform_async, ->(*_args, **_kwargs) { flunk "Job should not be enqueued without Sidekiq readiness" }) do
          post serp_search_customers_path, params: { limit: 1 }
        end
      end
    end

    assert_redirected_to draft_customers_path
    assert_includes flash[:alert], "Redis"
  end

  test "serp_search starts progress tracking and enqueues selected customer ids" do
    older = Customer.create!(company: "SERP Progress Older", status: "draft")
    newer = Customer.create!(company: "SERP Progress Newer", status: "draft")
    older.update_columns(updated_at: 2.hours.ago)
    newer.update_columns(updated_at: 1.hour.ago)

    ready = SerpSidekiqManager::Result.new(
      ready: true,
      started: false,
      message: "SERP専用Sidekiqは起動済みです。"
    )
    enqueued_args = nil
    progress_args = nil

    with_singleton_method(SerpSidekiqManager, :ensure_running, ->(*_args, **_kwargs) { ready }) do
      with_singleton_method(SerpProgressTracker, :start, ->(**kwargs) { progress_args = kwargs }) do
        with_singleton_method(SerpPipelineDbWorker, :perform_async, ->(*args) { enqueued_args = args }) do
          post serp_search_customers_path, params: { limit: 2 }
        end
      end
    end

    assert_redirected_to draft_customers_path
    assert_equal 2, enqueued_args[1]
    assert_equal [newer.id, older.id], enqueued_args[2]
    assert_match(/\A[0-9a-f]{24}\z/, enqueued_args[3])
    assert_equal enqueued_args[3], progress_args[:run_id]
    assert_equal 2, progress_args[:total]
    assert_equal [newer.id, older.id], progress_args[:target_ids]
    assert_includes flash[:notice], "進捗バー"
  end

  test "serp_search limits queued ids by company query" do
    target = Customer.create!(company: "SERP Company Query Target", status: "draft")
    Customer.create!(company: "SERP Company Query Other", status: "draft")

    ready = SerpSidekiqManager::Result.new(
      ready: true,
      started: false,
      message: "SERP専用Sidekiqは起動済みです。"
    )
    enqueued_args = nil
    progress_args = nil

    with_singleton_method(SerpSidekiqManager, :ensure_running, ->(*_args, **_kwargs) { ready }) do
      with_singleton_method(SerpProgressTracker, :start, ->(**kwargs) { progress_args = kwargs }) do
        with_singleton_method(SerpPipelineDbWorker, :perform_async, ->(*args) { enqueued_args = args }) do
          post serp_search_customers_path, params: { limit: 10, company_query: "Query Target" }
        end
      end
    end

    assert_redirected_to draft_customers_path
    assert_equal 1, enqueued_args[1]
    assert_equal [target.id], enqueued_args[2]
    assert_equal 1, progress_args[:total]
    assert_equal [target.id], progress_args[:target_ids]
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
