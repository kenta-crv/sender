require "test_helper"

class SerpSidekiqManagerTest < ActiveSupport::TestCase
  test "ensure_running is ready when worker is already running" do
    manager = Class.new(SerpSidekiqManager) do
      def worker_running?
        true
      end
    end.new

    result = manager.ensure_running(timeout: 0)

    assert result.ready?
    refute result.started?
    assert_includes result.message, "起動済み"
  end

  test "ensure_running blocks SERP start when Redis is unavailable" do
    manager = Class.new(SerpSidekiqManager) do
      def worker_running?
        false
      end

      def redis_reachable?
        false
      end
    end.new

    result = manager.ensure_running(timeout: 0)

    refute result.ready?
    refute result.started?
    assert_includes result.message, "Redis"
  end
end
