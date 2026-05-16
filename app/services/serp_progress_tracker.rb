# frozen_string_literal: true

class SerpProgressTracker
  TTL_SECONDS = 24.hours.to_i
  SERP_WEIGHT = 0.45
  WEB_WEIGHT = 0.55
  ETA_SAFETY_MULTIPLIER = ENV.fetch("SERP_ETA_SAFETY_MULTIPLIER", "1.35").to_f
  ETA_MIN_SECONDS_PER_TARGET = ENV.fetch("SERP_ETA_MIN_SECONDS_PER_TARGET", "48").to_f

  PHASE_LABELS = {
    "queued" => "開始待ち",
    "serp" => "SERP検索中",
    "web" => "Web補完中",
    "done" => "完了",
    "error" => "エラー"
  }.freeze

  def self.start(run_id:, total:, industry:, target_ids:)
    new(run_id).start(total: total, industry: industry, target_ids: target_ids)
  end

  def start(total:, industry:, target_ids:)
    write(
      run_id: run_id,
      phase: "queued",
      total: total.to_i,
      industry: industry.to_s,
      target_count: Array(target_ids).size,
      serp_total: total.to_i,
      serp_completed: 0,
      web_total: 0,
      web_completed: 0,
      done_count: 0,
      error_count: 0,
      started_at: Time.current.iso8601,
      updated_at: Time.current.iso8601,
      finished_at: "",
      message: "Sidekiqの処理開始待ち"
    )
  end

  def self.payload(run_id)
    return empty_payload if run_id.blank?

    new(run_id).payload
  end

  def initialize(run_id)
    @run_id = run_id.to_s
  end

  attr_reader :run_id

  def start_processing(total:)
    write(
      phase: "serp",
      total: total.to_i,
      serp_total: total.to_i,
      serp_completed: 0,
      updated_at: Time.current.iso8601,
      message: "SERP検索を開始しました"
    )
  end

  def serp_progress(completed:, total:)
    write(
      phase: "serp",
      serp_total: total.to_i,
      serp_completed: completed.to_i,
      updated_at: Time.current.iso8601,
      message: "SERP検索 #{completed.to_i}/#{total.to_i} 件"
    )
  end

  def web_started(total:)
    write(
      phase: "web",
      web_total: total.to_i,
      web_completed: 0,
      updated_at: Time.current.iso8601,
      message: total.to_i.positive? ? "Web補完を開始しました" : "Web補完対象はありません"
    )
  end

  def increment_web(message: nil)
    with_redis do |redis|
      redis.hincrby(key, "web_completed", 1)
      redis.hset(key, "phase", "web")
      redis.hset(key, "message", message.to_s.presence || "Web補完中")
      redis.hset(key, "updated_at", Time.current.iso8601)
      redis.expire(key, TTL_SECONDS)
    end
  rescue => e
    Rails.logger.warn("[SerpProgressTracker] increment_web failed: #{e.class} #{e.message}") if defined?(Rails)
    nil
  end

  def finish(done_count:, error_count:)
    write(
      phase: "done",
      done_count: done_count.to_i,
      error_count: error_count.to_i,
      serp_completed: numeric_payload[:serp_total],
      web_completed: numeric_payload[:web_total],
      updated_at: Time.current.iso8601,
      finished_at: Time.current.iso8601,
      message: "SERP補完が完了しました"
    )
  end

  def fail(message:)
    write(
      phase: "error",
      updated_at: Time.current.iso8601,
      finished_at: Time.current.iso8601,
      message: "SERP補完でエラーが発生しました: #{message}"
    )
  end

  def payload
    raw = read
    return self.class.empty_payload if raw.blank?

    numbers = numeric_payload(raw)
    phase = raw["phase"].presence || "queued"
    percent = progress_percent(numbers, phase)
    active = !%w[done error].include?(phase)
    started_at = parse_time(raw["started_at"])
    elapsed_seconds = started_at ? (Time.current - started_at).to_i : 0

    {
      present: true,
      run_id: @run_id,
      phase: phase,
      phase_label: PHASE_LABELS.fetch(phase, phase),
      active: active,
      percent: percent,
      total: numbers[:total],
      serp_completed: numbers[:serp_completed],
      serp_total: numbers[:serp_total],
      web_completed: numbers[:web_completed],
      web_total: numbers[:web_total],
      done_count: numbers[:done_count],
      error_count: numbers[:error_count],
      message: raw["message"].to_s,
      elapsed_label: self.class.format_duration(elapsed_seconds),
      eta_label: estimate_label(elapsed_seconds, percent, active, numbers: numbers, phase: phase),
      updated_at: raw["updated_at"].to_s
    }
  rescue => e
    Rails.logger.warn("[SerpProgressTracker] payload failed: #{e.class} #{e.message}") if defined?(Rails)
    self.class.empty_payload
  end

  def self.empty_payload
    {
      present: false,
      active: false,
      percent: 0.0,
      total: 0,
      serp_completed: 0,
      serp_total: 0,
      web_completed: 0,
      web_total: 0,
      done_count: 0,
      error_count: 0,
      phase: "none",
      phase_label: "未実行",
      message: "SERP補完は実行されていません",
      eta_label: "未計測",
      elapsed_label: "0秒"
    }
  end

  def self.format_duration(seconds, round_up: false)
    seconds = seconds.to_i
    return "1分未満" if seconds < 60

    minutes = round_up ? (seconds / 60.0).ceil : seconds / 60
    hours = minutes / 60
    remain_minutes = minutes % 60

    return "#{minutes}分" if hours.zero?
    return "#{hours}時間" if remain_minutes.zero?

    "#{hours}時間#{remain_minutes}分"
  end

  protected

  def write(attributes)
    with_redis do |redis|
      attributes.each do |field, value|
        redis.hset(key, field.to_s, value.to_s)
      end
      redis.expire(key, TTL_SECONDS)
    end
  rescue => e
    Rails.logger.warn("[SerpProgressTracker] write failed: #{e.class} #{e.message}") if defined?(Rails)
    nil
  end

  def read
    with_redis { |redis| redis.hgetall(key) } || {}
  rescue => e
    Rails.logger.warn("[SerpProgressTracker] read failed: #{e.class} #{e.message}") if defined?(Rails)
    {}
  end

  def key
    "serp_progress:#{@run_id}"
  end

  private

  def with_redis(&block)
    Sidekiq.redis(&block)
  end

  def numeric_payload(raw = read)
    {
      total: raw["total"].to_i,
      serp_total: raw["serp_total"].to_i,
      serp_completed: raw["serp_completed"].to_i,
      web_total: raw["web_total"].to_i,
      web_completed: raw["web_completed"].to_i,
      done_count: raw["done_count"].to_i,
      error_count: raw["error_count"].to_i
    }
  end

  def progress_percent(numbers, phase)
    return 100.0 if phase == "done"
    return 0.0 if numbers[:total].zero?

    serp_total = [numbers[:serp_total], 1].max
    serp_fraction = [numbers[:serp_completed].to_f / serp_total, 1.0].min

    web_total = numbers[:web_total]
    web_fraction = if web_total.positive?
      [numbers[:web_completed].to_f / web_total, 1.0].min
    elsif phase == "web"
      1.0
    else
      0.0
    end

    ((serp_fraction * SERP_WEIGHT + web_fraction * WEB_WEIGHT) * 100).round(1)
  end

  def estimate_label(elapsed_seconds, percent, active, numbers:, phase:)
    return "完了" unless active
    return "計測中" if percent.to_f <= 0.0

    estimates = []
    estimates << elapsed_seconds * ((100.0 - percent) / percent) * ETA_SAFETY_MULTIPLIER

    min_total_seconds = numbers[:total].to_i * ETA_MIN_SECONDS_PER_TARGET
    estimates << (min_total_seconds - elapsed_seconds)

    if phase == "web" && numbers[:web_total].positive? && numbers[:web_completed].positive?
      remaining_web = [numbers[:web_total] - numbers[:web_completed], 0].max
      estimates << (elapsed_seconds.to_f / numbers[:web_completed]) * remaining_web * ETA_SAFETY_MULTIPLIER
    end

    remaining = [estimates.compact.max.to_f.ceil, 0].max
    self.class.format_duration(remaining, round_up: true)
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end
end
