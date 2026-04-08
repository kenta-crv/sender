class FormSubmissionsController < ApplicationController
  before_action :set_batch, only: [:show, :cancel, :resume, :progress, :destroy]

  # GET /form_submissions
def index
  # -------------------------
  # 検索（Ransack）
  # -------------------------
  @q = Customer.ransack(params[:q])
  
  # 1. 検索条件に合致するベースのクエリ（この時点ではまだSQLは発行されない）
  base_customers_query = @q.result
                           .left_joins(:calls)

  # -------------------------
  # 未コール / 最終送信条件のフィルタリング
  # -------------------------
  if params[:last_call].present?
    lc = params[:last_call]
    statuses = Array(lc[:status]).reject(&:blank?)
    
    has_filter = lc[:calls_id_null] == "true" ||
                 statuses.any? ||
                 lc[:created_at_from].present? ||
                 lc[:created_at_to].present?

    if has_filter
      base_customers_query = base_customers_query.where('calls.call_type IS NULL OR calls.call_type = ?', 'form')

      base_customers_query = base_customers_query.where(calls: { id: nil }) if lc[:calls_id_null] == "true"
      base_customers_query = base_customers_query.where(calls: { status: statuses }) if statuses.any?
      base_customers_query = base_customers_query.where('calls.created_at >= ?', lc[:created_at_from]) if lc[:created_at_from].present?
      base_customers_query = base_customers_query.where('calls.created_at <= ?', lc[:created_at_to]) if lc[:created_at_to].present?
    end
  end

  # =====================================================
  # 顧客カテゴリ（ID抽出による高速化と重複削除）
  # =====================================================

  # A. 新規バッチ送信対象（contact_url 重複排除）
  # pluckでIDの配列だけをメモリに載せる（Customerオブジェクトを生成しないので軽い）
  target_ids = base_customers_query
                 .where.not(contact_url: [nil, '', 'not_detected'])
                 .group(:contact_url)
                 .pluck('MIN(customers.id)')

  @customers = Customer.where(id: target_ids)
                       .includes(:last_form_call)
                       .page(params[:customers_page])
                       .per(50)

  # B. フォームURL自動検出対象
  detectable_ids = base_customers_query
                     .where(contact_url: [nil, ''])
                     .where.not(url: [nil, ''])
                     .where(fobbiden: [nil, false, 0])
                     .group(:url) # URLが同じなら1件に絞る
                     .pluck('MIN(customers.id)')

  @detectable_customers = Customer.where(id: detectable_ids)
                                  .page(params[:detectable_page])
                                  .per(50)

  # C. 検出失敗済みの顧客数（カウントのみなのでシンプルに）
  @not_detected_count = Customer.where(contact_url: 'not_detected').count

  # D. URL完全未設定（カウントのみ）
  @no_url_customers_count = base_customers_query
                              .unscope(:left_joins) # カウントにJOINは不要
                              .where(contact_url: [nil, ''])
                              .where(url: [nil, ''])
                              .distinct
                              .count

  # -------------------------
  # Submission & バッチ集計（N+1回避）
  # -------------------------
  @submissions = Submission.order(created_at: :desc)
  @batches = FormSubmissionBatch.order(created_at: :desc).page(params[:page]).per(20)

  # バッチの統計情報を一括で取得
  batch_stats = FormSubmissionBatch.group(:submission_id)
                                   .select(
                                     :submission_id,
                                     'SUM(total_count) AS total_sent',
                                     'SUM(success_count) AS success_count',
                                     'SUM(failure_count) AS failure_count',
                                     'MAX(started_at) AS last_sent_at'
                                   ).index_by(&:submission_id)

  @submission_stats = @submissions.map do |submission|
    stat = batch_stats[submission.id]
    {
      submission: submission,
      total_sent:    stat&.total_sent || 0,
      success_count: stat&.success_count || 0,
      failure_count: stat&.failure_count || 0,
      last_sent_at:  stat&.last_sent_at
    }
  end
end
  # POST /form_submissions
  def create
    # 送信対象: indexの@customersと同じスコープ（contact_url設定済み）
    eligible_scope = Customer.where.not(contact_url: [nil, '', 'not_detected'])
                             .where(fobbiden: [nil, false, 0])
                             .order(:id)

    # 検索条件（Ransack）を適用
    if params[:q].present?
      eligible_scope = eligible_scope.ransack(params[:q]).result
    end

    # 最終送信条件を適用
    if params[:last_call].present?
      lc = params[:last_call]
      statuses = Array(lc[:status]).reject(&:blank?)
      has_filter = lc[:calls_id_null] == "true" ||
                   statuses.any? ||
                   lc[:created_at_from].present? ||
                   lc[:created_at_to].present?

      if has_filter
        eligible_scope = eligible_scope.left_joins(:calls).distinct
                           .where('calls.call_type IS NULL OR calls.call_type = ?', 'form')

        if lc[:calls_id_null] == "true"
          eligible_scope = eligible_scope.where(calls: { id: nil })
        end

        if statuses.any?
          eligible_scope = eligible_scope.where(calls: { status: statuses })
        end

        if lc[:created_at_from].present?
          eligible_scope = eligible_scope.where('calls.created_at >= ?', lc[:created_at_from])
        end

        if lc[:created_at_to].present?
          eligible_scope = eligible_scope.where('calls.created_at <= ?', lc[:created_at_to])
        end
      end
    end

    send_count = params[:send_count].to_i if params[:send_count].present?

    customer_ids = if params[:select_all] == '1'
                     # 全件選択 → ページネーションに関係なく全対象顧客を取得
                     eligible_scope.pluck(:id)
                   elsif params[:customer_ids].present?
                     Array(params[:customer_ids]).map(&:to_i)
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
    customer_ids = if params[:detect_select_all] == '1'
                     # 全件選択 → ページネーションに関係なく全対象顧客を取得
                     Customer.where(contact_url: [nil, ''])
                             .where.not(url: [nil, ''])
                             .where(fobbiden: [nil, false, 0])
                             .pluck(:id)
                   else
                     Array(params[:customer_ids]).map(&:to_i)
                   end

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

  # POST /form_submissions/:id/resume
  def resume
    unprocessed = @batch.unprocessed_customer_ids

    if unprocessed.empty?
      redirect_to form_submission_path(@batch), alert: '未処理の顧客はありません。'
      return
    end

    # ステータスを処理中に戻し、合計件数を更新
    @batch.update!(
      status: 'processing',
      total_count: @batch.processed_count + unprocessed.size,
      completed_at: nil
    )

    # 未処理分のみ再キュー
    unprocessed.each do |cid|
      FormSendJob.perform_later(@batch.id, cid)
    end

    redirect_to form_submission_path(@batch), notice: "#{unprocessed.size}件の未処理分を再開しました。"
  end

  # GET /form_submissions/:id/progress (JSON)
  def progress
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    render json: @batch.progress_payload
  end

  def update_manual
    @submission = Submission.find(params[:id])
    if @submission.update(manual: params[:manual] == '1')
      respond_to do |format|
        format.html { redirect_to form_submissions_path, notice: 'Manualフラグを更新しました。' }
        format.json { render json: { status: 'ok', manual: @submission.manual } }
      end
    else
      respond_to do |format|
        format.html { redirect_to form_submissions_path, alert: '更新に失敗しました。' }
        format.json { render json: { status: 'error' }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    if @batch.destroy
      redirect_to form_submissions_path, notice: 'バッチ送信履歴を削除しました。'
    else
      redirect_to form_submissions_path, alert: '削除に失敗しました。'
    end
  end

  private

  def set_batch
    @batch = FormSubmissionBatch.find(params[:id])
  end
end
