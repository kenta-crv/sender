class FormSubmissionsController < ApplicationController
  before_action :set_batch, only: [:show, :cancel, :progress]

  # GET /form_submissions
  def index
    @batches = FormSubmissionBatch.order(created_at: :desc).page(params[:page]).per(20)
    # contact_url設定済みの顧客（送信可能）
    @customers = Customer.where.not(contact_url: [nil, '']).includes(:last_form_call)
    # url有りだがcontact_url未設定の顧客（自動検出対象）
    @detectable_customers = Customer.where(contact_url: [nil, ''])
                                    .where.not(url: [nil, ''])
                                    .where(fobbiden: [nil, false, 0])
                                    .includes(:last_form_call)
    # url も contact_url もない顧客（手動設定が必要）
    @no_url_customers_count = Customer.where(contact_url: [nil, ''])
                                      .where(url: [nil, ''])
                                      .count
  end

  # POST /form_submissions
  def create
    # contact_url有り or url有り（自動検出付き）の顧客を対象に
    eligible_scope = Customer.where(
      'contact_url IS NOT NULL AND contact_url != ? OR (url IS NOT NULL AND url != ?)', '', ''
    ).where(fobbiden: [nil, false, 0])

    send_count = params[:send_count].to_i if params[:send_count].present?

    customer_ids = if params[:customer_ids].present?
                     Array(params[:customer_ids]).map(&:to_i)
                   elsif params[:q].present?
                     q = eligible_scope.ransack(params[:q])
                     q.result.pluck(:id)
                   elsif send_count && send_count > 0
                     # 件数指定のみ（チェックなし）→ eligible_scopeから先頭N件
                     eligible_scope.limit(send_count).pluck(:id)
                   else
                     []
                   end

    # 件数指定がある場合、チェック済みでも件数で切り詰め
    if send_count && send_count > 0 && customer_ids.size > send_count
      customer_ids = customer_ids.first(send_count)
    end

    if customer_ids.empty?
      redirect_to form_submissions_path, alert: '送信対象の顧客が選択されていません。件数を指定するか、顧客を選択してください。'
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

  # POST /form_submissions/detect_contact_urls
  def detect_contact_urls
    customer_ids = Array(params[:customer_ids]).map(&:to_i)

    if customer_ids.empty?
      redirect_to form_submissions_path, alert: '検出対象の顧客が選択されていません。'
      return
    end

    ContactUrlDetectJob.perform_later(customer_ids)

    redirect_to form_submissions_path, notice: "#{customer_ids.size}件のお問い合わせフォームURL自動検出を開始しました。"
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
