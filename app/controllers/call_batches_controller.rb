class CallBatchesController < ApplicationController
  before_action :set_batch, only: [:show, :pause, :resume, :cancel, :progress]

  # GET /call_batches/dashboard
  def dashboard
    @active_calls = Call.auto_calls.active_twilio
                        .includes(:customer)
                        .order(started_at: :desc)
    @current_batch = CallBatch.where(status: 'processing').last
    @recent_calls = Call.auto_calls
                        .where.not(twilio_status: ['initiated', 'ringing', 'in-progress'])
                        .order(ended_at: :desc)
                        .limit(50)
                        .includes(:customer)
    @stats = {
      today_total: Call.auto_calls.call_count_today.count,
      today_answered: Call.auto_calls.call_count_today.where(twilio_status: 'completed').where.not(answered_at: nil).count,
      today_transferred: Call.auto_calls.call_count_today.where(flow_phase: 'transfer').count
    }

    respond_to do |format|
      format.html
      format.json { render json: { active_calls: @active_calls.as_json(include: :customer), stats: @stats } }
    end
  end

  # GET /call_batches/analytics
  def analytics
    @from = analytics_parse_date(params[:from]) || Time.current.to_date.beginning_of_month
    @to = analytics_parse_date(params[:to]) || Time.current.to_date
    @from, @to = @to, @from if @from > @to

    current_calls = analytics_calls_between(@from.beginning_of_day, @to.end_of_day)
    period_days = (@to - @from).to_i + 1
    prev_to = @from - 1.day
    prev_from = prev_to - (period_days - 1).days
    previous_calls = analytics_calls_between(prev_from.beginning_of_day, prev_to.end_of_day)

    @kpis = analytics_kpis(current_calls)
    @prev_kpis = analytics_kpis(previous_calls)
    @result_counts = analytics_result_counts(current_calls)
    @result_total = @result_counts.values.sum
    @daily_labels = (@from..@to).to_a
    grouped = current_calls.group_by { |call| analytics_call_date(call) }
    @daily_dials = @daily_labels.map { |day| (grouped[day] || []).size }
    @daily_connected = @daily_labels.map { |day| (grouped[day] || []).count { |call| analytics_connected?(call) } }
    @batch_rows = analytics_batch_rows(current_calls)
  end

  # GET /call_batches
  def index
    @batches = CallBatch.order(created_at: :desc).page(params[:page]).per(20)
  end

  # GET /call_batches/new
  def new
    @q = Customer.ransack(call_batch_search_params)
    @customers = call_batch_eligible_customers.page(params[:page]).per(100)
    @clients = Client.order(:name)
    latest_ids = Call.auto_calls.where(customer_id: @customers.map(&:id)).group(:customer_id).maximum(:id)
    @last_auto_calls = Call.where(id: latest_ids.values).index_by(&:customer_id)
  end

  # POST /call_batches
  def create
    eligible_scope = call_batch_eligible_customers

    send_count = params[:send_count].to_i if params[:send_count].present?

    customer_ids = if params[:select_all] == '1'
                     eligible_scope.pluck(:id)
                   elsif params[:customer_ids].present?
                     Array(params[:customer_ids]).map(&:to_i)
                   elsif send_count && send_count > 0
                     eligible_scope.limit(send_count).pluck(:id)
                   else
                     []
                   end

    if send_count && send_count > 0 && customer_ids.size > send_count
      customer_ids = customer_ids.first(send_count)
    end

    if customer_ids.empty?
      redirect_to new_call_batch_path(
        q: call_batch_search_params.to_h,
        call_history: params[:call_history],
        last_call_from: params[:last_call_from],
        last_call_to: params[:last_call_to],
        last_call_result: params[:last_call_result]
      ), alert: '発信対象の顧客が選択されていません。'
      return
    end

    concurrent_lines = 1

    batch = CallBatch.create!(
      name: params[:name].presence || "自動発信 #{Time.current.strftime('%Y/%m/%d %H:%M')}",
      total_count: customer_ids.size,
      customer_ids: customer_ids.to_json,
      status: 'processing',
      started_at: Time.current,
      concurrent_lines: concurrent_lines,
      worker_id: current_admin&.id || current_worker&.id
    )

    AutoDialBatchJob.perform_later(batch.id)

    redirect_to call_batch_path(batch), notice: "自動発信を開始しました（#{customer_ids.size}件、#{concurrent_lines}回線）"
  end

  # GET /call_batches/:id
  def show
    @calls = Call.auto_calls
                 .where(call_batch_id: @batch.id)
                 .includes(:customer)
                 .order(created_at: :desc)
                 .page(params[:page])
                 .per(50)
  end

  # PATCH /call_batches/:id/pause
  def pause
    @batch.pause!
    redirect_to call_batch_path(@batch), notice: '発信を一時停止しました。'
  end

  # PATCH /call_batches/:id/resume
  def resume
    @batch.resume!
    unprocessed = @batch.unprocessed_customer_ids
    if unprocessed.any?
      unprocessed.each { |cid| AutoDialJob.perform_later(@batch.id, cid) }
    end
    redirect_to call_batch_path(@batch), notice: "発信を再開しました（残り#{unprocessed.size}件）"
  end

  # PATCH /call_batches/:id/cancel
  def cancel
    @batch.cancel!
    redirect_to call_batch_path(@batch), notice: '発信をキャンセルしました。'
  end

  # GET /call_batches/:id/progress (JSON)
  def progress
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    render json: @batch.progress_payload
  end

  private

  def set_batch
    @batch =
      if action_name == 'show'
        CallBatch.without_payload_columns.find(params[:id])
      else
        CallBatch.find(params[:id])
      end
  end

  def call_batch_search_params
    params.fetch(:q, {}).permit(
      :company_cont, :business_cont, :tel_cont, :ceo_cont, :genre_cont,
      :status_eq, :client_id_eq
    )
  end
  helper_method :call_batch_search_params

  def call_batch_filter_params
    params.permit(:call_history, :last_call_from, :last_call_to, :last_call_result, :page)
  end
  helper_method :call_batch_filter_params

  def analytics_parse_date(value)
    return if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def analytics_calls_between(from_time, to_time)
    Call.auto_calls
        .where('COALESCE(started_at, created_at) BETWEEN ? AND ?', from_time, to_time)
        .includes(:call_batch)
        .to_a
  end

  def analytics_call_date(call)
    (call.started_at || call.created_at).in_time_zone.to_date
  end

  def analytics_connected?(call)
    call.answered_at.present?
  end

  def analytics_appointment?(call)
    call.flow_phase == 'transfer' || %w[transfer inquiry].include?(call.speech_category)
  end

  def analytics_result_key(call)
    if analytics_connected?(call)
      :connected
    elsif call.twilio_status == 'busy'
      :busy
    elsif %w[no-answer canceled].include?(call.twilio_status) || call.speech_category == 'absent'
      :absent
    else
      :other
    end
  end

  def analytics_kpis(calls)
    durations = calls.map(&:duration).compact
    {
      dials: calls.size,
      connected: calls.count { |call| analytics_connected?(call) },
      appointments: calls.count { |call| analytics_appointment?(call) },
      avg_duration: durations.any? ? (durations.sum.to_f / durations.size) : 0
    }
  end

  def analytics_result_counts(calls)
    counts = { connected: 0, absent: 0, busy: 0, other: 0 }
    calls.each { |call| counts[analytics_result_key(call)] += 1 }
    counts
  end

  def analytics_batch_rows(calls)
    grouped = calls.group_by(&:call_batch_id)
    rows = grouped.map do |batch_id, batch_calls|
      batch = batch_calls.find { |call| call.call_batch }&.call_batch
      dials = batch_calls.size
      connected = batch_calls.count { |call| analytics_connected?(call) }
      appointments = batch_calls.count { |call| analytics_appointment?(call) }
      {
        name: batch&.name.presence || '未分類',
        dials: dials,
        connected: connected,
        appointments: appointments,
        appointment_rate: dials.positive? ? (appointments.to_f / dials * 100) : 0
      }
    end
    rows.sort_by { |row| -row[:dials] }
  end

  def analytics_delta(current, previous)
    return if previous.to_f.zero?

    ((current.to_f - previous.to_f) / previous.to_f * 100).round(0)
  end
  helper_method :analytics_delta

  def analytics_duration_label(seconds)
    total = seconds.to_f.round
    format('%d:%02d', total / 60, total % 60)
  end
  helper_method :analytics_duration_label

  def analytics_pct(part, total)
    total.to_f.positive? ? (part.to_f / total * 100).round(1) : 0.0
  end
  helper_method :analytics_pct

  def analytics_spark_svg(values, color: '#34d399')
    vals = Array(values)
    return ''.html_safe if vals.empty?

    w = 54
    h = 18
    max_v = [vals.max, 1].max
    pts = vals.each_with_index.map do |v, i|
      x = vals.size == 1 ? w / 2.0 : (w.to_f * i / (vals.size - 1))
      y = h - 2 - (v.to_f / max_v * (h - 4))
      "#{x},#{y}"
    end.join(' ')
    %(<svg viewBox="0 0 #{w} #{h}" class="da-spark">#{ %(<polyline fill="none" stroke="#{color}" stroke-width="1.6" points="#{pts}" />) }</svg>).html_safe
  end
  helper_method :analytics_spark_svg

  def analytics_line_svg(series, width: 640, height: 240, show_dots: true)
    labels = @daily_labels
    return '' if labels.empty?

    pad_l = 36
    pad_r = 16
    pad_t = 18
    pad_b = 32
    plot_w = width - pad_l - pad_r
    plot_h = height - pad_t - pad_b
    max_v = [series.map { |s| s[:values].max || 0 }.max, 1].max
    x_at = lambda do |i|
      return pad_l.to_f if labels.size == 1

      pad_l + plot_w.to_f * i / (labels.size - 1)
    end
    y_at = ->(v) { pad_t + plot_h - (v.to_f / max_v * plot_h) }

    grid = 4.times.map do |g|
      val = (max_v * (4 - g) / 4.0).round
      gy = y_at.call(val)
      %(<line x1="#{pad_l}" y1="#{gy}" x2="#{width - pad_r}" y2="#{gy}" stroke="rgba(148,163,184,0.18)" stroke-width="1"/>) +
        %(<text x="8" y="#{gy + 4}" fill="rgba(148,163,184,0.55)" font-size="9">#{val}</text>)
    end.join

    ticks = labels.each_with_index.map do |day, i|
      next unless i.zero? || i == labels.size - 1 || (i % [((labels.size / 6.0).ceil), 1].max).zero?

      %(<text x="#{x_at.call(i)}" y="#{height - 8}" fill="rgba(148,163,184,0.55)" font-size="9" text-anchor="middle">#{day.strftime('%-m/%-d')}</text>)
    end.join

    bodies = series.map do |s|
      pts = s[:values].each_with_index.map { |v, i| "#{x_at.call(i)},#{y_at.call(v)}" }
      point_str = pts.join(' ')
      first = "#{x_at.call(0)},#{y_at.call(0)}"
      last = "#{x_at.call(s[:values].size - 1)},#{y_at.call(0)}"
      marks = if show_dots
                s[:values].each_with_index.map do |v, i|
                  %(<circle cx="#{x_at.call(i)}" cy="#{y_at.call(v)}" r="2.6" fill="#{s[:color]}" />)
                end.join
              else
                ''
              end
      area = s[:fill] ? %(<polygon points="#{first} #{point_str} #{last}" fill="#{s[:fill]}" />) : ''
      %(#{area}<polyline fill="none" stroke="#{s[:color]}" stroke-width="2.2" points="#{point_str}" />#{marks})
    end.join

    %(<svg viewBox="0 0 #{width} #{height}" preserveAspectRatio="none" class="da-chart-svg">#{grid}#{bodies}#{ticks}</svg>).html_safe
  end
  helper_method :analytics_line_svg

  def analytics_donut_svg
    parts = [
      [@result_counts[:connected], '#38bdf8'],
      [@result_counts[:absent], '#60a5fa'],
      [@result_counts[:busy], '#94a3b8'],
      [@result_counts[:other], '#475569']
    ]
    total = parts.sum(&:first).to_f
    radius = 52
    circ = 2 * Math::PI * radius
    offset = 0.0
    rings = if total <= 0
              %(<circle cx="80" cy="80" r="#{radius}" fill="none" stroke="rgba(148,163,184,0.2)" stroke-width="16" />)
            else
              parts.map do |count, color|
                len = circ * (count / total)
                dash = %(#{len} #{circ - len})
                ring = %(<circle cx="80" cy="80" r="#{radius}" fill="none" stroke="#{color}" stroke-width="16" stroke-dasharray="#{dash}" stroke-dashoffset="#{-offset}" transform="rotate(-90 80 80)" />)
                offset += len
                ring
              end.join
            end
    %(<svg viewBox="0 0 160 160" class="da-donut-svg">#{rings}<text x="80" y="76" text-anchor="middle" fill="#ffffff" font-size="22" font-weight="700">#{@kpis[:dials]}</text><text x="80" y="96" text-anchor="middle" fill="rgba(148,163,184,0.9)" font-size="11">総発信数</text></svg>).html_safe
  end
  helper_method :analytics_donut_svg

  def call_batch_eligible_customers
    rel = Customer.ransack(call_batch_search_params).result
                  .where.not(tel: [nil, ''])
                  .where("fobbiden IS NULL OR fobbiden != 'true'")
                  .includes(:client)

    auto_ids = Call.auto_calls.select(:customer_id)

    case params[:call_history]
    when 'never'
      rel = rel.where.not(id: auto_ids)
    when 'called'
      rel = rel.where(id: auto_ids)
    end

    if params[:last_call_from].present? || params[:last_call_to].present? || params[:last_call_result].present?
      last_ids_sql = Call.auto_calls.select('customer_id, MAX(id) AS last_id').group(:customer_id).to_sql
      rel = rel.joins(<<~SQL.squish)
        INNER JOIN (#{last_ids_sql}) last_auto_ids ON last_auto_ids.customer_id = customers.id
        INNER JOIN calls last_auto_calls ON last_auto_calls.id = last_auto_ids.last_id
      SQL
      if params[:last_call_from].present?
        rel = rel.where('COALESCE(last_auto_calls.started_at, last_auto_calls.created_at) >= ?', Time.zone.parse(params[:last_call_from]).beginning_of_day)
      end
      if params[:last_call_to].present?
        rel = rel.where('COALESCE(last_auto_calls.started_at, last_auto_calls.created_at) <= ?', Time.zone.parse(params[:last_call_to]).end_of_day)
      end
      if params[:last_call_result].present?
        rel = rel.where('last_auto_calls.speech_category = :r OR last_auto_calls.flow_phase = :r', r: params[:last_call_result])
      end
    end

    rel.distinct
  end
end
