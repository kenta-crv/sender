class Client::DashboardController < ApplicationController
  before_action :authenticate_client!

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
    # カウント系（ご指定の2項目のみ current_client に限定）
    # -------------------------
    @not_detected_count = Customer.where(client_id: current_client.id)
                                  .where(contact_url: 'not_detected')
                                  .count

    @no_url_customers_count = Customer.where(client_id: current_client.id)
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
    # KPI（今月分のみに限定）
    # -------------------------
    current_month_range = Time.current.beginning_of_month..Time.current.end_of_month
    @monthly_batches = current_client.form_submission_batches.where(created_at: current_month_range)

    @total_sent    = @monthly_batches.sum(:total_count)
    @total_success = @monthly_batches.sum(:success_count)
    @total_failure = @monthly_batches.sum(:failure_count)

    @success_rate =
      if @total_sent > 0
        ((@total_success.to_f / @total_sent) * 100).round(1)
      else
        0
      end

    # -------------------------
    # Active Jobs（←これ重要）
    # -------------------------
    @active_jobs = @batches.where(status: 'processing').count
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
    # @submission_stats の定義（nilエラー解決用）
    # ---------------------------------------------------------
    @submissions = current_client.submissions.order(created_at: :desc)
    @submission_stats = @submissions.map do |submission|
      # current_client に紐づくバッチのみを集計
      batches = submission.form_submission_batches.where(client_id: current_client.id)

      total_sent    = batches.sum(:total_count)
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

  def sending
    # -------------------------
    # 1. 権限によるベーススコープ
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
    # 2. 検索（Ransack）
    # -------------------------
    @q = base_scope.includes(:last_form_call).ransack(params[:q])
    filtered = @q.result(distinct: true)

    # -------------------------
    # 3. 送信対象顧客の抽出（排他処理の徹底）
    # -------------------------
    excluded_statuses = ['フォーム未検出', 'アクセス失敗', 'エラー', 'not_detected']

    @customers = filtered
                   .where.not(contact_url: [nil, '', 'not_detected'])
                   .left_joins(:last_form_call)
                   .where("calls.status NOT IN (?) OR calls.id IS NULL", excluded_statuses)
                   .page(params[:customers_page]).per(50)

    # 4. 自動検出待ちリスト
    @detectable_customers = filtered
                              .where(contact_url: [nil, ''])
                              .where.not(url: [nil, ''])
                              .where(fobbiden: [nil, false, 0])
                              .page(params[:detectable_page]).per(50)

    # -------------------------
    # 5. カウント処理
    # -------------------------
    @customers_count = @customers.total_count
    @detectable_count = @detectable_customers.total_count

    @not_detected_count = base_scope.left_joins(:last_form_call)
                                    .where(contact_url: 'not_detected')
                                    .or(base_scope.where(calls: { status: excluded_statuses }))
                                    .distinct.count
  end

  def searching_form
    # -------------------------
    # 自分の顧客のみに限定 (client_id を指定)
    # -------------------------
    base_customers = Customer.where(client_id: current_client.id)
                             .includes(:last_form_call)
                             .left_joins(:calls)
                             .distinct

    # -------------------------
    # 検索（Ransack）
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
    # カウント系
    # -------------------------
    @not_detected_count = Customer.where(client_id: current_client.id)
                                  .where(contact_url: 'not_detected')
                                  .count

    @no_url_customers_count = Customer.where(client_id: current_client.id)
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
    # @submission_stats の定義（nilエラー解決用）
    # ---------------------------------------------------------
    @submissions = current_client.submissions.order(created_at: :desc)
    @submission_stats = @submissions.map do |submission|
      # current_client に紐づくバッチのみを集計
      batches = submission.form_submission_batches.where(client_id: current_client.id)

      total_sent    = batches.sum(:total_count)
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


def sending
  # -------------------------
  # 1. 権限によるベーススコープ
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
  # 2. 検索（Ransack）
  # -------------------------
  @q = base_scope.includes(:last_form_call).ransack(params[:q])
  filtered = @q.result(distinct: true)

  # -------------------------
  # 3. 送信対象顧客の抽出（排他処理の徹底）
  # -------------------------
  # 除外すべきステータスリスト
  excluded_statuses = ['フォーム未検出', 'アクセス失敗', 'エラー', 'not_detected']

  # 送信可能リスト：
  # contact_url があり、かつ直近のコールステータスが「送信不可」なものではない顧客のみ
  @customers = filtered
                 .where.not(contact_url: [nil, '', 'not_detected'])
                 .left_joins(:last_form_call)
                 .where("calls.status NOT IN (?) OR calls.id IS NULL", excluded_statuses)
                 .page(params[:customers_page]).per(50)

  # 4. 自動検出待ちリスト
  @detectable_customers = filtered
                            .where(contact_url: [nil, ''])
                            .where.not(url: [nil, ''])
                            .where(fobbiden: [nil, false, 0])
                            .page(params[:detectable_page]).per(50)

  # -------------------------
  # 5. カウント処理
  # -------------------------
  @customers_count = @customers.total_count
  @detectable_count = @detectable_customers.total_count

  # 送信不可（検出失敗）の合計数
  @not_detected_count = base_scope.left_joins(:last_form_call)
                                  .where(contact_url: 'not_detected')
                                  .or(base_scope.where(calls: { status: excluded_statuses }))
                                  .distinct.count
end

def searching_form
    # -------------------------
    # 自分の顧客のみに限定 (client_id を指定)
    # -------------------------
    base_customers = Customer.where(client_id: current_client.id)
                                   .includes(:last_form_call)
                                   .left_joins(:calls)
                                   .distinct

    # -------------------------
    # 検索（Ransack）
    # -------------------------
    @q = base_customers.ransack(params[:q])
    filtered = @q.result(distinct: true)

    # -------------------------
    # 自動検出対象 (自分の顧客かつ未検出のもの)
    # -------------------------
    @detectable_customers = filtered
                              .where(contact_url: [nil, ''])
                              .where.not(url: [nil, ''])
                              .where(fobbiden: [nil, false, 0])
                              .page(params[:detectable_page]).per(50)

    # -------------------------
    # カウント系 (ここも current_client の範囲に限定)
    # -------------------------
    # フォーム検出を試みたが 'not_detected' だった自分の顧客
    @not_detected_count = Customer.where(client_id: current_client.id)
                                  .where(contact_url: 'not_detected')
                                  .count

    # HP URLすら設定されていない自分の顧客
    @no_url_customers_count = Customer.where(client_id: current_client.id)
                                            .where(contact_url: [nil, ''])
                                            .where(url: [nil, ''])
                                            .count

    # -------------------------
    # Submission（Viewのエラー回避用に追加）
    # -------------------------
    @submissions = current_client.submissions.order(created_at: :desc)
  end

  def setting
  end
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
    # @submission_stats の定義（nilエラー解決用）
    # ---------------------------------------------------------
    @submissions = current_client.submissions.order(created_at: :desc)
    @submission_stats = @submissions.map do |submission|
      # current_client に紐づくバッチのみを集計
      batches = submission.form_submission_batches.where(client_id: current_client.id)

      total_sent    = batches.sum(:total_count)
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