require "test_helper"

class CustomersControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @original_bright_data_api_key = ENV["BRIGHT_DATA_API_KEY"]
    ENV["BRIGHT_DATA_API_KEY"] = "test-bright-data-api-key"

    admin = Admin.create!(
      email: "admin-#{SecureRandom.hex(6)}@example.com",
      password: "password",
      password_confirmation: "password"
    )
    sign_in admin
  end

  teardown do
    restore_env("BRIGHT_DATA_API_KEY", @original_bright_data_api_key)
  end

  test "draft filters customers by company query" do
    target = Customer.create!(company: "Draft Company Query Target", status: "draft")
    other = Customer.create!(company: "Draft Company Query Other", status: "draft")

    get draft_customers_path, params: { company_query: "Query Target" }

    assert_response :success
    assert_includes @response.body, target.company
    refute_includes @response.body, other.company
  end

  test "draft keeps selected industry visible even when all records are already processed" do
    Customer.create!(
      company: "株式会社登録支援機関テスト",
      status: "draft",
      serp_status: "serp_done",
      business: "登録支援機関"
    )

    get draft_customers_path, params: { industry_name: "登録支援機関" }

    assert_response :success
    assert_includes @response.body, "登録支援機関（1件）"
  end

  test "serp_search does not fall back to synchronous pipeline when sidekiq is unavailable" do
    Customer.create!(company: "株式会社SERP Sidekiq Guard Test", status: "draft")

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

    assert_redirected_to dashboard_index_path
    assert_includes flash[:alert], "Redis"
  end

  test "serp_search stops before enqueue when bright data api key is missing" do
    customer = Customer.create!(company: "株式会社SERP Missing API Key Test", status: "draft")

    with_env("BRIGHT_DATA_API_KEY", nil) do
      with_singleton_method(SerpSidekiqManager, :ensure_running, ->(*_args, **_kwargs) { flunk "Sidekiq should not start without BrightData API key" }) do
        with_singleton_method(SerpPipelineDbWorker, :perform_async, ->(*_args, **_kwargs) { flunk "Job should not be enqueued without BrightData API key" }) do
          post serp_search_customers_path, params: { limit: 1 }
        end
      end
    end

    assert_redirected_to dashboard_index_path
    assert_includes flash[:alert], "BRIGHT_DATA_API_KEY"
    assert_nil customer.reload.serp_status
  end

  test "serp_search starts progress tracking and enqueues selected customer ids" do
    older = Customer.create!(company: "株式会社SERP Progress Older", status: "draft")
    newer = Customer.create!(company: "株式会社SERP Progress Newer", status: "draft")
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
        with_singleton_method(SerpPipelineDbWorker, :perform_async, ->(*args) { enqueued_args = args; "jid-controller-1" }) do
          post serp_search_customers_path, params: { limit: 2 }
        end
      end
    end

    assert_redirected_to dashboard_index_path
    assert_equal [newer.id, older.id], enqueued_args[1]
    assert_equal 0, enqueued_args[3]
    assert_match(/\A[0-9a-f]{24}\z/, enqueued_args[2])
    assert_equal enqueued_args[2], progress_args[:run_id]
    assert_equal 2, progress_args[:total]
    assert_equal [newer.id, older.id], progress_args[:target_ids]
    audit_run = SerpEnrichmentRun.find_by_run_id(progress_args[:run_id])
    assert_equal "jid-controller-1", audit_run.jid
    assert_equal [newer.id, older.id], audit_run.targets.order(:position).pluck(:customer_id)
    assert_equal ["SERP Progress Newer", "SERP Progress Older"], audit_run.targets.order(:position).pluck(:company)
    assert_includes flash[:notice], "進捗バー"
    assert_includes flash[:notice], "SERP Progress Newer(ID:#{newer.id})"
  end

  test "serp_search limits queued ids by company query" do
    target = Customer.create!(company: "株式会社SERP Company Query Target", status: "draft")
    Customer.create!(company: "株式会社SERP Company Query Other", status: "draft")

    ready = SerpSidekiqManager::Result.new(
      ready: true,
      started: false,
      message: "SERP専用Sidekiqは起動済みです。"
    )
    enqueued_args = nil
    progress_args = nil

    with_singleton_method(SerpSidekiqManager, :ensure_running, ->(*_args, **_kwargs) { ready }) do
      with_singleton_method(SerpProgressTracker, :start, ->(**kwargs) { progress_args = kwargs }) do
        with_singleton_method(SerpPipelineDbWorker, :perform_async, ->(*args) { enqueued_args = args; "jid-controller-query" }) do
          post serp_search_customers_path, params: { limit: 10, company_query: "Query Target" }
        end
      end
    end

    assert_redirected_to dashboard_index_path
    assert_equal [target.id], enqueued_args[1]
    assert_equal 0, enqueued_args[3]
    assert_equal 1, progress_args[:total]
    assert_equal [target.id], progress_args[:target_ids]
  end

  test "serp_search can requeue done customer when company query is explicit" do
    target = Customer.create!(
      company: "株式会社SERP Explicit Done Target",
      status: "draft",
      serp_status: "serp_done",
      tel: "090-0000-0000",
      address: "Tokyo",
      url: "https://example.com",
      contact_url: "https://example.com/contact"
    )
    Customer.create!(company: "株式会社SERP Explicit Done Other", status: "draft", serp_status: "serp_done")

    ready = SerpSidekiqManager::Result.new(
      ready: true,
      started: false,
      message: "SERP Sidekiq is ready"
    )
    enqueued_args = nil
    progress_args = nil

    with_singleton_method(SerpSidekiqManager, :ensure_running, ->(*_args, **_kwargs) { ready }) do
      with_singleton_method(SerpProgressTracker, :start, ->(**kwargs) { progress_args = kwargs }) do
        with_singleton_method(SerpPipelineDbWorker, :perform_async, ->(*args) { enqueued_args = args; "jid-controller-explicit" }) do
          post serp_search_customers_path, params: { limit: 10, company_query: "Explicit Done Target" }
        end
      end
    end

    assert_redirected_to dashboard_index_path
    assert_equal [target.id], enqueued_args[1]
    assert_equal 0, enqueued_args[3]
    assert_equal 1, progress_args[:total]
    assert_equal [target.id], progress_args[:target_ids]
  end

  private

  def with_env(key, value)
    original = ENV[key]
    restore_env(key, value)
    yield
  ensure
    restore_env(key, original)
  end

  def restore_env(key, value)
    if value.nil?
      ENV.delete(key)
    else
      ENV[key] = value
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
end
