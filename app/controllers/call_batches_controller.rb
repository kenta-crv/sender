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

  # GET /call_batches
  def index
    @batches = CallBatch.order(created_at: :desc).page(params[:page]).per(20)
  end

  # GET /call_batches/new
  def new
    @q = Customer.ransack(params[:q])
    @customers = @q.result
                   .where.not(tel: [nil, ''])
                   .where(fobbiden: [nil, false, 0])
                   .page(params[:page]).per(100)
  end

  # POST /call_batches
  def create
    eligible_scope = Customer.where.not(tel: [nil, ''])
                             .where(fobbiden: [nil, false, 0])

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
      redirect_to new_call_batch_path, alert: '発信対象の顧客が選択されていません。'
      return
    end

    concurrent_lines = (params[:concurrent_lines] || 3).to_i.clamp(1, 5)

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
    @batch = CallBatch.find(params[:id])
  end
end
