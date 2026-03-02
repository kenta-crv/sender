class FormSubmissionsController < ApplicationController
  before_action :set_batch, only: [:show, :cancel, :progress]

  # GET /form_submissions
def index
  # -------------------------
  # 検索（Ransack）
  # -------------------------
  @q = Customer.ransack(params[:q])
  base_customers = @q.result
                     .includes(:last_form_call)
                     .left_joins(:calls)
                     .distinct

  # -------------------------
  # 未コール / 最終送信条件
  # -------------------------
  if params[:last_call].present?
    lc = params[:last_call]

    base_customers = base_customers
                       .where('calls.call_type IS NULL OR calls.call_type = ?', 'form')

    # 未コール
    if lc[:calls_id_null] == "true"
      base_customers = base_customers.where(calls: { id: nil })
    end

    # 最終送信状態
    if lc[:status].present?
      base_customers = base_customers.where(calls: { status: lc[:status] })
    end

    # 最終送信日時（開始）
    if lc[:created_at_from].present?
      base_customers = base_customers.where('calls.created_at >= ?', lc[:created_at_from])
    end

    # 最終送信日時（終了）
    if lc[:created_at_to].present?
      base_customers = base_customers.where('calls.created_at <= ?', lc[:created_at_to])
    end
  end

  # =====================================================
  # 顧客カテゴリ（ここで明確に排他）
  # =====================================================

  # 新規バッチ送信対象（contact_url 設定済み）
  @customers = base_customers
                 .where.not(contact_url: [nil, ''])

  # フォームURL自動検出対象（contact_url 未設定 ＆ HP URLあり）
  @detectable_customers = base_customers
                            .where(contact_url: [nil, ''])
                            .where.not(url: [nil, ''])
                            .where(fobbiden: [nil, false, 0])

  # URL完全未設定（カウントのみ）
  @no_url_customers = base_customers
                        .where(contact_url: [nil, ''])
                        .where(url: [nil, ''])
  
  @no_url_customers_count = @no_url_customers.count
  # -------------------------
  # Submission
  # -------------------------
  @submissions = Submission.order(created_at: :desc)

  # -------------------------
  # バッチ一覧
  # -------------------------
  @batches = FormSubmissionBatch.order(created_at: :desc)
                                .page(params[:page])
                                .per(20)

  # -------------------------
  # Submission別送信件数集計
  # -------------------------
  @submission_stats = @submissions.map do |submission|
    batches = submission.form_submission_batches

    total_sent   = batches.sum(:total_count)
    success_count = batches.sum(:success_count)
    failure_count = batches.sum(:failure_count)
    last_sent_at  = batches.order(started_at: :desc)
                            .limit(1)
                            .pluck(:started_at)
                            .first

    {
      submission: submission,
      total_sent: total_sent,
      success_count: success_count,
      failure_count: failure_count,
      last_sent_at: last_sent_at
    }
  end
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
      status: 'processing',
      started_at: Time.current,
      error_log: '[]',
      submission_id: params[:submission_id].presence
    )

    # 並列処理: 各顧客を独立したジョブとしてキューに投入
    customer_ids.each do |cid|
      FormSendJob.perform_later(batch.id, cid)
    end

    redirect_to form_submission_path(batch), notice: "バッチ送信を開始しました（#{customer_ids.size}件）"
  end

  # POST /form_submissions/detect_contact_urls
  def detect_contact_urls
    customer_ids = Array(params[:customer_ids]).map(&:to_i)

    if customer_ids.empty?
      redirect_to form_submissions_path, alert: '検出対象の顧客が選択されていません。'
      return
    end

    # 並列処理: 各顧客を独立したジョブとしてキューに投入
    customer_ids.each do |cid|
      ContactUrlDetectJob.perform_later(cid)
    end

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
