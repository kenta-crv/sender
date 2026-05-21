require "fileutils"
require "rbconfig"
require "socket"
require "uri"

class SerpSidekiqManager
  QUEUE_NAME = "serp_enrichment".freeze
  CONFIG_PATH = Rails.root.join("config", "sidekiq_enrichment.yml")
  LOG_PATH = Rails.root.join("log", "sidekiq_serp_enrichment.log")
  PID_PATH = Rails.root.join("tmp", "pids", "sidekiq_serp_enrichment.pid")
  REDIS_LOG_PATH = Rails.root.join("log", "redis_serp_enrichment.log")
  REDIS_PID_PATH = Rails.root.join("tmp", "pids", "redis_serp_enrichment.pid")
  BOOT_TIMEOUT_SECONDS = ENV.fetch("SERP_SIDEKIQ_BOOT_TIMEOUT", "10").to_f
  REDIS_BOOT_TIMEOUT_SECONDS = ENV.fetch("SERP_REDIS_BOOT_TIMEOUT", "10").to_f
  LOCAL_REDIS_HOSTS = %w[localhost 127.0.0.1 ::1].freeze

  Result = Struct.new(:ready, :message, :started, :redis_started, keyword_init: true) do
    def ready?
      !!ready
    end

    def started?
      !!started
    end

    def redis_started?
      !!redis_started
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

  def self.redis_auto_start_possible?
    new.redis_auto_start_possible?
  end

  def ensure_running(timeout: BOOT_TIMEOUT_SECONDS)
    return ready_result(started: false) if worker_running?

    redis = ensure_redis_running(timeout: REDIS_BOOT_TIMEOUT_SECONDS)
    return redis unless redis.ready?

    unless auto_start_enabled?
      return Result.new(
        ready: false,
        started: false,
        redis_started: redis.redis_started?,
        message: manual_start_message
      )
    end

    started = start_worker_process
    unless started
      return Result.new(
        ready: false,
        started: false,
        redis_started: redis.redis_started?,
        message: manual_start_message
      )
    end

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      return ready_result(started: true, redis_started: redis.redis_started?) if worker_running?

      sleep 0.5
    end

    return ready_result(started: true, redis_started: redis.redis_started?) if auto_started_process_alive?

    Result.new(
      ready: false,
      started: true,
      redis_started: redis.redis_started?,
      message: "SERP専用Sidekiqを起動しましたが、起動確認が時間内に取れませんでした。log/sidekiq_serp_enrichment.log を確認してください。"
    )
  end

  def redis_reachable?
    uri = redis_uri
    Socket.tcp(uri.host, uri.port, connect_timeout: 0.4) { true }
  rescue StandardError
    false
  end

  def redis_auto_start_possible?
    redis_auto_start_allowed? && redis_server_command.present?
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

  def ready_result(started:, redis_started: false)
    message = if started && redis_started
      "RedisとSERP専用Sidekiqを起動しました。"
    elsif started
      "SERP専用Sidekiqを起動しました。"
    else
      "SERP専用Sidekiqは起動済みです。"
    end

    Result.new(
      ready: true,
      started: started,
      redis_started: redis_started,
      message: message
    )
  end

  def auto_start_enabled?
    ENV.fetch("SERP_AUTO_START_SIDEKIQ", "1") != "0"
  end

  def auto_start_redis_enabled?
    ENV.fetch("SERP_AUTO_START_REDIS", "1") != "0"
  end

  def ensure_redis_running(timeout:)
    return Result.new(ready: true, started: false, redis_started: false, message: "Redisは起動済みです。") if redis_reachable?

    unless auto_start_redis_enabled?
      return Result.new(
        ready: false,
        started: false,
        redis_started: false,
        message: "Redisに接続できないため、SERP補完を開始できませんでした。Redisを起動してから再実行してください。"
      )
    end

    unless redis_auto_start_allowed?
      return Result.new(
        ready: false,
        started: false,
        redis_started: false,
        message: "REDIS_URLがローカルではないため、Redisは自動起動しません。Redis接続を確認してから再実行してください。"
      )
    end

    unless start_redis_process
      return Result.new(
        ready: false,
        started: false,
        redis_started: false,
        message: manual_redis_start_message
      )
    end

    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      return Result.new(ready: true, started: false, redis_started: true, message: "Redisを起動しました。") if redis_reachable?

      sleep 0.5
    end

    Result.new(
      ready: false,
      started: false,
      redis_started: true,
      message: "Redisを起動しましたが、接続確認が時間内に取れませんでした。log/redis_serp_enrichment.log を確認してください。"
    )
  end

  def redis_auto_start_allowed?
    uri = redis_uri
    return false unless uri.scheme == "redis"

    LOCAL_REDIS_HOSTS.include?(uri.host.to_s.downcase)
  rescue StandardError
    false
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

  def start_redis_process
    return true if auto_started_redis_process_alive?

    command = redis_server_command
    return false if command.blank?

    FileUtils.mkdir_p(REDIS_LOG_PATH.dirname)
    FileUtils.mkdir_p(REDIS_PID_PATH.dirname)

    pid = Process.spawn(
      command,
      "--port",
      redis_uri.port.to_s,
      chdir: Rails.root.to_s,
      out: [REDIS_LOG_PATH.to_s, "a"],
      err: [:child, :out]
    )
    Process.detach(pid)
    REDIS_PID_PATH.write("#{pid}\n")
    Rails.logger.info("[SerpSidekiqManager] started Redis pid=#{pid}")
    true
  rescue StandardError => e
    Rails.logger.warn("[SerpSidekiqManager] failed to start Redis: #{e.class} #{e.message}")
    false
  end

  def spawn_env
    env = {
      "RAILS_ENV" => Rails.env,
      "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s
    }

    %w[
      BRIGHT_DATA_API_KEY
      REDIS_URL
      SERP_AUTO_START_SIDEKIQ
      SERP_AUTO_START_REDIS
      REDIS_SERVER_PATH
    ].each do |key|
      env[key] = ENV[key] if ENV[key].present?
    end

    env
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

  def auto_started_redis_process_alive?
    return false unless REDIS_PID_PATH.exist?

    pid = REDIS_PID_PATH.read.to_i
    return false if pid.zero?

    Process.kill(0, pid)
    true
  rescue Errno::ESRCH, Errno::EINVAL
    REDIS_PID_PATH.delete if REDIS_PID_PATH.exist?
    false
  rescue StandardError
    false
  end

  def redis_uri
    URI.parse(ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
  end

  def redis_server_command
    candidates = [
      ENV["REDIS_SERVER_PATH"],
      ("C:/Program Files/Redis/redis-server.exe" if Gem.win_platform?),
      find_executable("redis-server")
    ].compact

    candidates.find { |path| File.file?(path) && File.executable?(path) }
  end

  def find_executable(name)
    exts = Gem.win_platform? ? ENV.fetch("PATHEXT", ".COM;.EXE;.BAT;.CMD").split(";") : [""]
    ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).each do |dir|
      exts.each do |ext|
        path = File.join(dir, "#{name}#{ext}")
        return path if File.file?(path) && File.executable?(path)
      end
    end
    nil
  end

  def manual_start_message
    "SERP専用Sidekiqを起動できませんでした。別ターミナルで bundle exec sidekiq -C config/sidekiq_enrichment.yml を起動してから再実行してください。"
  end

  def manual_redis_start_message
    "Redisを起動できませんでした。別ターミナルで redis-server を起動してから再実行してください。"
  end
end
