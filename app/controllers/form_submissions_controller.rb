class FormSubmissionsController < ApplicationController
  before_action :set_batch, only: [:show, :cancel, :progress]

  # GET /form_submissions
  def index
    @batches = FormSubmissionBatch.order(created_at: :desc).page(params[:page]).per(20)
    @customers = Customer.where.not(contact_url: [nil, ''])
  end

  # POST /form_submissions
  def create
    customer_ids = if params[:customer_ids].present?
                     Array(params[:customer_ids]).map(&:to_i)
                   elsif params[:q].present?
                     # Ransack 検索結果から全件取得
                     q = Customer.where.not(contact_url: [nil, '']).ransack(params[:q])
                     q.result.pluck(:id)
                   else
                     []
                   end

    if customer_ids.empty?
      redirect_to form_submissions_path, alert: '送信対象の顧客が選択されていません。'
      return
    end

    batch = FormSubmissionBatch.create!(
      total_count: customer_ids.size,
      customer_ids: customer_ids.to_json,
      status: 'pending',
      error_log: '[]'
    )

    FormSendJob.perform_later(batch.id, 0)

    redirect_to form_submission_path(batch), notice: "バッチ送信を開始しました（#{customer_ids.size}件）"
  end

  # GET /form_submissions/:id
  def show
    @results = Call.form_submissions
                   .where(customer_id: @batch.parsed_customer_ids)
                   .where('calls.created_at >= ?', @batch.created_at)
                   .includes(:customer)
                   .order(created_at: :desc)
  end

  # PATCH /form_submissions/:id/cancel
  def cancel
    @batch.cancel!
    redirect_to form_submission_path(@batch), notice: 'バッチ送信をキャンセルしました。'
  end

  # GET /form_submissions/:id/progress (JSON)
  def progress
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    render json: @batch.progress_payload
  end

  private

  def set_batch
    @batch = FormSubmissionBatch.find(params[:id])
  end
end
