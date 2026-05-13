require "fileutils"
require "rbconfig"
require "socket"
require "uri"

class SerpSidekiqManager
  QUEUE_NAME = "serp_enrichment".freeze
  CONFIG_PATH = Rails.root.join("config", "sidekiq_enrichment.yml")
  LOG_PATH = Rails.root.join("log", "sidekiq_serp_enrichment.log")
  PID_PATH = Rails.root.join("tmp", "pids", "sidekiq_serp_enrichment.pid")
  BOOT_TIMEOUT_SECONDS = ENV.fetch("SERP_SIDEKIQ_BOOT_TIMEOUT", "10").to_f

  Result = Struct.new(:ready, :message, :started, keyword_init: true) do
    def ready?
      !!ready
    end

    def started?
      !!started
    end
  end

  def self.ensure_running(timeout: BOOT_TIMEOUT_SECONDS)
    new.ensure_running(timeout: timeout)
  end

  def self.redis_reachable?
    new.redis_reachable?
  end

  def self.worker_running?
    new.worker_running?
  end

  def self.queue_size
    new.queue_size
  end

  def ensure_running(timeout: BOOT_TIMEOUT_SECONDS)
    return ready_result(started: false) if worker_running?

    unless redis_reachable?
      return Result.new(
        ready: false,
        started: false,
        message: "Redisに接続できないため、SERP補完を開始できませんでした。Redisを起動してから再実行してください。"
      )
    end

    unless auto_start_enabled?
      return Result.new(
        ready: false,
        started: false,
        message: manual_start_message
      )
    end

    started = start_worker_process
    return Result.new(ready: false, started: false, message: manual_start_message) unless started

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      return ready_result(started: true) if worker_running?

      sleep 0.5
    end

    Result.new(
      ready: false,
      started: true,
      message: "SERP専用Sidekiqを起動しましたが、起動確認が時間内に取れませんでした。log/sidekiq_serp_enrichment.log を確認してください。"
    )
  end

  def redis_reachable?
    uri = URI.parse(ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
    Socket.tcp(uri.host, uri.port, connect_timeout: 0.4) { true }
  rescue StandardError
    false
  end

  def worker_running?
    return false unless redis_reachable?

    require "sidekiq/api"
    Sidekiq::ProcessSet.new.any? do |process|
      queues = process["queues"].to_a
      queues.include?(QUEUE_NAME) || queues.include?("default")
    end
  rescue Redis::CannotConnectError, Errno::ECONNREFUSED, StandardError
    false
  end

  def queue_size
    return nil unless redis_reachable?

    require "sidekiq/api"
    Sidekiq::Queue.new(QUEUE_NAME).size
  rescue Redis::CannotConnectError, Errno::ECONNREFUSED, StandardError
    nil
  end

  private

  def ready_result(started:)
    Result.new(
      ready: true,
      started: started,
      message: started ? "SERP専用Sidekiqを起動しました。" : "SERP専用Sidekiqは起動済みです。"
    )
  end

  def auto_start_enabled?
    ENV.fetch("SERP_AUTO_START_SIDEKIQ", "1") != "0"
  end

  def start_worker_process
    return true if auto_started_process_alive?

    FileUtils.mkdir_p(LOG_PATH.dirname)
    FileUtils.mkdir_p(PID_PATH.dirname)

    pid = Process.spawn(
      spawn_env,
      RbConfig.ruby,
      Gem.bin_path("bundler", "bundle"),
      "exec",
      "sidekiq",
      "-C",
      CONFIG_PATH.relative_path_from(Rails.root).to_s,
      chdir: Rails.root.to_s,
      out: [LOG_PATH.to_s, "a"],
      err: [:child, :out]
    )
    Process.detach(pid)
    PID_PATH.write("#{pid}\n")
    Rails.logger.info("[SerpSidekiqManager] started Sidekiq pid=#{pid}")
    true
  rescue StandardError => e
    Rails.logger.warn("[SerpSidekiqManager] failed to start Sidekiq: #{e.class} #{e.message}")
    false
  end

  def spawn_env
    {
      "RAILS_ENV" => Rails.env,
      "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s
    }
  end

  def auto_started_process_alive?
    return false unless PID_PATH.exist?

    pid = PID_PATH.read.to_i
    return false if pid.zero?

    Process.kill(0, pid)
    true
  rescue Errno::ESRCH, Errno::EINVAL
    PID_PATH.delete if PID_PATH.exist?
    false
  rescue StandardError
    false
  end

  def manual_start_message
    "SERP専用Sidekiqを起動できませんでした。別ターミナルで bundle exec sidekiq -C config/sidekiq_enrichment.yml を起動してから再実行してください。"
  end
end
