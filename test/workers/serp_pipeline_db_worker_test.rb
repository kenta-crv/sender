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
