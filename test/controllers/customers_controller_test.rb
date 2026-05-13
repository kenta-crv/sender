require "test_helper"

class CustomersControllerTest < ActionDispatch::IntegrationTest
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
