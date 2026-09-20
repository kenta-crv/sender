# frozen_string_literal: true

require "json"

class SerpProgressTracker
  TTL_SECONDS = 24.hours.to_i
  TARGET_PREVIEW_LIMIT = 20
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
    ids = Array(target_ids).map(&:to_i).reject(&:zero?).uniq
    write(
      run_id: run_id,
      phase: "queued",
      total: total.to_i,
      industry: industry.to_s,
      target_count: ids.size,
      target_total: ids.size,
      target_completed: 0,
      target_ids: ids.join(","),
      target_preview: JSON.generate(target_preview_for(ids)),
      target_preview_limit: TARGET_PREVIEW_LIMIT,
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
      target_total: total.to_i,
      target_completed: 0,
      updated_at: Time.current.iso8601,
      message: total.to_i.positive? ? "Web補完を開始しました" : "Web補完対象はありません"
    )
  end

  def increment_web(message: nil)
    with_redis do |redis|
      redis.hincrby(key, "web_completed", 1)
      redis.hincrby(key, "target_completed", 1)
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
    numbers = numeric_payload
    target_total = numbers[:target_total].positive? ? numbers[:target_total] : numbers[:total]
    web_total = numbers[:web_total].positive? ? numbers[:web_total] : target_total

    write(
      phase: "done",
      done_count: done_count.to_i,
      error_count: error_count.to_i,
      target_total: target_total,
      target_completed: target_total,
      serp_completed: numbers[:serp_total],
      web_total: web_total,
      web_completed: web_total,
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
    audit_run = audit_run_for(@run_id)
    phase = raw["phase"].presence || "queued"
    phase = audit_run.status if audit_run && %w[done error].include?(audit_run.status)
    percent = progress_percent(numbers, phase)
    active = !%w[done error].include?(phase)
    started_at = audit_run&.started_at || parse_time(raw["started_at"])
    elapsed_seconds = started_at ? (Time.current - started_at).to_i : 0

    target_ids = parse_target_ids(raw["target_ids"])
    target_preview = current_target_preview(parse_target_preview(raw["target_preview"]), target_ids)
    target_preview = audit_target_preview(audit_run, target_preview) if audit_run

    {
      present: true,
      run_id: @run_id,
      jid: audit_run&.jid.to_s,
      run_status: audit_run&.status.to_s,
      sidekiq_status: audit_run&.sidekiq_status.to_s,
      phase: phase,
      phase_label: PHASE_LABELS.fetch(phase, phase),
      active: active,
      percent: percent,
      total: numbers[:total],
      target_total: numbers[:target_total],
      target_completed: [numbers[:target_completed], numbers[:target_total]].min,
      target_preview: target_preview,
      target_preview_limit: raw["target_preview_limit"].to_i.positive? ? raw["target_preview_limit"].to_i : TARGET_PREVIEW_LIMIT,
      serp_completed: numbers[:serp_completed],
      serp_total: numbers[:serp_total],
      web_completed: numbers[:web_completed],
      web_total: numbers[:web_total],
      done_count: numbers[:done_count],
      error_count: numbers[:error_count],
      message: raw["message"].to_s,
      elapsed_label: self.class.format_duration(elapsed_seconds),
      eta_label: estimate_label(elapsed_seconds, percent, active, numbers: numbers, phase: phase),
      started_at: started_at&.iso8601.to_s,
      finished_at: audit_run&.finished_at&.iso8601.to_s,
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
      target_total: 0,
      target_completed: 0,
      target_preview: [],
      target_preview_limit: TARGET_PREVIEW_LIMIT,
      run_id: nil,
      jid: nil,
      run_status: nil,
      sidekiq_status: nil,
      started_at: nil,
      finished_at: nil,
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
    target_total = raw["target_total"].presence || raw["target_count"].presence || raw["total"]
    target_completed = raw["target_completed"].presence || raw["web_completed"]

    {
      total: raw["total"].to_i,
      target_total: target_total.to_i,
      target_completed: target_completed.to_i,
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
    return 0.0 if numbers[:target_total].zero?

    serp_total = [numbers[:serp_total], 1].max
    serp_fraction = [numbers[:serp_completed].to_f / serp_total, 1.0].min

    target_fraction = if numbers[:target_total].positive?
      [numbers[:target_completed].to_f / numbers[:target_total], 1.0].min
    else
      0.0
    end

    case phase
    when "serp"
      (serp_fraction * SERP_WEIGHT * 100).round(1)
    when "web"
      ((SERP_WEIGHT + target_fraction * WEB_WEIGHT) * 100).round(1)
    when "error"
      ((SERP_WEIGHT + target_fraction * WEB_WEIGHT) * 100).round(1)
    else
      0.0
    end
  end

  def estimate_label(elapsed_seconds, percent, active, numbers:, phase:)
    return "完了" unless active
    return "計測中" if percent.to_f <= 0.0

    estimates = []
    estimates << elapsed_seconds * ((100.0 - percent) / percent) * ETA_SAFETY_MULTIPLIER

    min_total_seconds = numbers[:target_total].to_i * ETA_MIN_SECONDS_PER_TARGET
    estimates << (min_total_seconds - elapsed_seconds)

    if phase == "web" && numbers[:target_total].positive? && numbers[:target_completed].positive?
      remaining_targets = [numbers[:target_total] - numbers[:target_completed], 0].max
      estimates << (elapsed_seconds.to_f / numbers[:target_completed]) * remaining_targets * ETA_SAFETY_MULTIPLIER
    end

    remaining = [estimates.compact.max.to_f.ceil, 0].max
    self.class.format_duration(remaining, round_up: true)
  end

  def parse_time(value)
    Time.zone.parse(value.to_s)
  rescue ArgumentError, TypeError
    nil
  end

  def target_preview_for(target_ids)
    ids = Array(target_ids).map(&:to_i).reject(&:zero?).first(TARGET_PREVIEW_LIMIT)
    customer_model = customer_model_class
    return [] if ids.empty? || customer_model.blank?

    records = customer_model.where(id: ids).select(:id, :company, :serp_status, :url).index_by(&:id)
    ids.filter_map do |id|
      customer = records[id]
      next if customer.blank?

      {
        id: customer.id,
        company: customer.company.to_s,
        serp_status: customer.serp_status.to_s,
        serp_status_label: serp_status_label_for(customer.serp_status),
        hp_url: customer.url.to_s
      }
    end
  end

  def parse_target_preview(value)
    JSON.parse(value.to_s).map do |item|
      {
        id: item["id"].to_i,
        company: item["company"].to_s,
        serp_status: item["serp_status"].to_s,
        serp_status_label: item["serp_status_label"].to_s.presence || serp_status_label_for(item["serp_status"]),
        hp_url: item["hp_url"].to_s.presence || item["url"].to_s
      }
    end
  rescue JSON::ParserError, TypeError
    []
  end

  def parse_target_ids(value)
    value.to_s.split(",").map(&:to_i).reject(&:zero?).uniq
  end

  def current_target_preview(stored_preview, target_ids)
    ids = target_ids.presence || stored_preview.map { |item| item[:id].to_i }.reject(&:zero?)
    customer_model = customer_model_class
    return stored_preview if ids.empty? || customer_model.blank?

    records = customer_model.where(id: ids.first(TARGET_PREVIEW_LIMIT))
                            .select(:id, :company, :serp_status, :url)
                            .index_by(&:id)
    ids.first(TARGET_PREVIEW_LIMIT).filter_map do |id|
      stored = stored_preview.find { |item| item[:id].to_i == id } || {}
      customer = records[id]
      if customer
        {
          id: customer.id,
          company: customer.company.to_s,
          serp_status: customer.serp_status.to_s,
          serp_status_label: serp_status_label_for(customer.serp_status),
          hp_url: customer.url.to_s
        }
      elsif stored.present?
        stored
      end
    end
  rescue => e
    Rails.logger.warn("[SerpProgressTracker] current target preview failed: #{e.class} #{e.message}") if defined?(Rails)
    stored_preview
  end

  def audit_run_for(value)
    model = "SerpEnrichmentRun".safe_constantize
    return nil if model.blank?

    model.find_by_run_id(value)
  rescue => e
    Rails.logger.warn("[SerpProgressTracker] audit run lookup failed: #{e.class} #{e.message}") if defined?(Rails)
    nil
  end

  def audit_target_preview(audit_run, fallback_preview)
    targets = audit_run.targets.order(:position).limit(TARGET_PREVIEW_LIMIT).to_a
    return fallback_preview if targets.empty?

    customer_model = customer_model_class
    customers = if customer_model
      customer_model.where(id: targets.map(&:customer_id))
                    .select(:id, :company, :serp_status, :url)
                    .index_by(&:id)
    else
      {}
    end

    targets.map do |target|
      customer = customers[target.customer_id]
      current_status = customer&.serp_status.presence ||
                       target.after_serp_status.presence ||
                       target.before_serp_status
      update_keys = Array(target.update_keys).reject(&:blank?)

      {
        id: target.customer_id,
        company: (target.company.presence || customer&.company).to_s,
        serp_status: current_status.to_s,
        serp_status_label: serp_status_label_for(current_status),
        before_serp_status: target.before_serp_status.to_s,
        before_serp_status_label: serp_status_label_for(target.before_serp_status),
        result_status: target.result_status.to_s,
        result_status_label: run_result_label_for(target.result_status),
        candidate_count: target.candidate_count.to_i,
        selected_url: target.selected_url.to_s,
        hp_url: customer&.url.to_s.presence || target.after_url.to_s.presence || target.selected_url.to_s,
        update_keys: update_keys,
        update_keys_label: update_keys.any? ? update_keys.join(", ") : "-"
      }
    end
  rescue => e
    Rails.logger.warn("[SerpProgressTracker] audit target preview failed: #{e.class} #{e.message}") if defined?(Rails)
    fallback_preview
  end

  def customer_model_class
    "Customer".safe_constantize
  end

  def serp_status_label_for(value)
    case value
    when nil, ""         then "未処理"
    when "serp_queued"   then "処理中"
    when "serp_done"     then "完了"
    when "serp_imported" then "登録済み"
    when "serp_error"    then "エラー"
    else value.to_s
    end
  end

  def run_result_label_for(value)
    case value.to_s
    when "", "pending"   then "待機中"
    when "updated"       then "更新あり"
    when "url_only"      then "URLのみ"
    when "no_candidate"  then "候補なし"
    when "excluded"      then "除外URLのみ"
    when "no_update"     then "更新なし"
    when "error"         then "エラー"
    else value.to_s
    end
  end
end
