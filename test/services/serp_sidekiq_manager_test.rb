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

      def auto_start_redis_enabled?
        false
      end
    end.new

    result = manager.ensure_running(timeout: 0)

    refute result.ready?
    refute result.started?
    assert_includes result.message, "Redis"
  end

  test "ensure_running starts local Redis before Sidekiq" do
    manager = Class.new(SerpSidekiqManager) do
      def initialize
        @redis_started = false
        @worker_started = false
      end

      def worker_running?
        @worker_started
      end

      def redis_reachable?
        @redis_started
      end

      def redis_auto_start_allowed?
        true
      end

      def auto_start_redis_enabled?
        true
      end

      def start_redis_process
        @redis_started = true
      end

      def auto_start_enabled?
        true
      end

      def start_worker_process
        @worker_started = true
      end
    end.new

    result = manager.ensure_running(timeout: 0.1)

    assert result.ready?
    assert result.started?
    assert result.redis_started?
    assert_includes result.message, "Redis"
  end

  test "ensure_running is ready when started Sidekiq process is still booting" do
    manager = Class.new(SerpSidekiqManager) do
      def worker_running?
        false
      end

      def redis_reachable?
        true
      end

      def auto_start_enabled?
        true
      end

      def start_worker_process
        true
      end

      def auto_started_process_alive?
        true
      end
    end.new

    result = manager.ensure_running(timeout: 0)

    assert result.ready?
    assert result.started?
    refute result.redis_started?
    assert_includes result.message, "起動しました"
  end

  test "redis auto start is unavailable for remote Redis URL" do
    manager = Class.new(SerpSidekiqManager) do
      def redis_uri
        URI.parse("redis://redis.example.com:6379/0")
      end

      def redis_server_command
        "redis-server"
      end
    end.new

    refute manager.redis_auto_start_possible?
  end
end
