class Client::DashboardController < ApplicationController
  before_action :authenticate_client!

  def index
    # -------------------------
    # 自分の顧客のみ
    # -------------------------
    base_customers = Customer
                                   .includes(:last_form_call)
                                   .left_joins(:calls)
                                   .distinct

    # -------------------------
    # 検索（Ransack）
    # -------------------------
    @q = base_customers.ransack(params[:q])
    filtered = @q.result(distinct: true)

    # -------------------------
    # 送信可能顧客
    # -------------------------
    @customers = filtered
                   .where.not(contact_url: [nil, '', 'not_detected'])
                   .page(params[:customers_page]).per(20)

    # -------------------------
    # 検出対象
    # -------------------------
    @detectable_customers = filtered
                              .where(contact_url: [nil, ''])
                              .where.not(url: [nil, ''])
                              .where(fobbiden: [nil, false, 0])
                              .page(params[:detectable_page]).per(20)

    # -------------------------
    # カウント系
    # -------------------------
    @not_detected_count = Customer.where(contact_url: 'not_detected').count

    @no_url_customers_count = Customer
                                            .where(contact_url: [nil, ''])
                                            .where(url: [nil, ''])
                                            .count

    # -------------------------
    # Submission（client限定）
    # -------------------------
    @submissions = current_client.submissions.order(created_at: :desc)

    # -------------------------
    # Batch（client限定）
    # -------------------------
    @batches = current_client.form_submission_batches
                             .order(created_at: :desc)
                             .page(params[:page])
                             .per(10)

    # -------------------------
    # KPI
    # -------------------------
    @total_sent    = @batches.sum(:total_count)
    @total_success = @batches.sum(:success_count)
    @total_failure = @batches.sum(:failure_count)

    @success_rate =
      if @total_sent > 0
        ((@total_success.to_f / @total_sent) * 100).round(1)
      else
        0
      end

    # -------------------------
    # Active Jobs
    # -------------------------
    @active_jobs = current_client.form_submission_batches
                                 .where(status: ['pending', 'processing'])
                                 .count

    @active_batch = current_client.form_submission_batches
                                  .where(status: ['pending', 'processing'])
                                  .order(created_at: :desc)
                                  .first
  end

  def history
    # ---------------------------------------------------------
    # 履歴ページ（_history.html.slim）で必要な変数を定義
    # ---------------------------------------------------------
    @q = Customer.ransack(params[:q])

    @batches = current_client.form_submission_batches
                             .order(created_at: :desc)
                             .page(params[:page])
                             .per(20)

    # ---------------------------------------------------------
    # Submission統計
    # ---------------------------------------------------------
    @submissions = current_client.submissions.order(created_at: :desc)

    @submission_stats = @submissions.map do |submission|
      batches = submission.form_submission_batches.where(client_id: current_client.id)

      total_sent    = batches.sum(:total_count)
      success_count = batches.sum(:success_count)
      failure_count = batches.sum(:failure_count)

      last_sent_at = batches
                      .order(started_at: :desc)
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

  def sending
    # -------------------------
    # 1. 権限制御
    # -------------------------
    if admin_signed_in?
      base_scope = Customer.all
      @submissions = Submission.order(created_at: :desc)

    elsif client_signed_in?
      base_scope = Customer.where(client_id: [current_client.id, nil])
      @submissions = current_client.submissions.order(created_at: :desc)

    else
      base_scope = Customer.none
      @submissions = Submission.none
    end

    # -------------------------
    # 2. 検索
    # -------------------------
    @q = base_scope.includes(:last_form_call).ransack(params[:q])
    filtered = @q.result(distinct: true)

    # -------------------------
    # 3. 送信対象
    # -------------------------
    excluded_statuses = [
      'フォーム未検出',
      'アクセス失敗',
      'エラー',
      'not_detected'
    ]

    @customers = filtered
                   .where.not(contact_url: [nil, '', 'not_detected'])
                   .left_joins(:last_form_call)
                   .where(
                     "calls.status NOT IN (?) OR calls.id IS NULL",
                     excluded_statuses
                   )
                   .page(params[:customers_page]).per(50)

    # -------------------------
    # 4. 自動検出待ち
    # -------------------------
    @detectable_customers = filtered
                              .where(contact_url: [nil, ''])
                              .where.not(url: [nil, ''])
                              .where(fobbiden: [nil, false, 0])
                              .page(params[:detectable_page]).per(50)

    # -------------------------
    # 5. カウント
    # -------------------------
    @customers_count = @customers.total_count
    @detectable_count = @detectable_customers.total_count

    @not_detected_count = base_scope
                            .left_joins(:last_form_call)
                            .where(contact_url: 'not_detected')
                            .or(base_scope.where(calls: { status: excluded_statuses }))
                            .distinct
                            .count
  end

  def searching_form
    # -------------------------
    # 自分の顧客のみ
    # -------------------------
    base_customers = Customer
                       .where(client_id: current_client.id)
                       .includes(:last_form_call)
                       .left_joins(:calls)
                       .distinct

    # -------------------------
    # 検索
    # -------------------------
    @q = base_customers.ransack(params[:q])
    filtered = @q.result(distinct: true)

    # -------------------------
    # 自動検出対象
    # -------------------------
    @detectable_customers = filtered
                              .where(contact_url: [nil, ''])
                              .where.not(url: [nil, ''])
                              .where(fobbiden: [nil, false, 0])
                              .page(params[:detectable_page]).per(50)

    # -------------------------
    # カウント
    # -------------------------
    @not_detected_count = Customer
                            .where(client_id: current_client.id)
                            .where(contact_url: 'not_detected')
                            .count

    @no_url_customers_count = Customer
                                .where(client_id: current_client.id)
                                .where(contact_url: [nil, ''])
                                .where(url: [nil, ''])
                                .count

    # -------------------------
    # Submission
    # -------------------------
    @submissions = current_client.submissions.order(created_at: :desc)
  end

  def setting
  end
end