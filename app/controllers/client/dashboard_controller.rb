class Client::DashboardController < ApplicationController
  before_action :authenticate_client!

class Client::DashboardController < ApplicationController
  before_action :authenticate_client!

  def index
    # -------------------------
    # 自分の顧客のみ
    # -------------------------
    base_customers = current_client.customers
                                   .includes(:last_form_call)
                                   .left_joins(:calls)
                                   .distinct

    # -------------------------
    # 検索（Ransack）
    # -------------------------
    @q = base_customers.ransack(params[:q])
    filtered = @q.result

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
    @not_detected_count = current_client.customers.where(contact_url: 'not_detected').count

    @no_url_customers_count = current_client.customers
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
    # Active Jobs（←これ重要）
    # -------------------------
    @active_jobs = @batches.where(status: 'processing').count
  end

  def history
    # ---------------------------------------------------------
    # 履歴ページ（_history.html.slim）で必要な変数を定義
    # ---------------------------------------------------------
    @q = current_client.customers.ransack(params[:q])
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
    # 検索オブジェクト @q がないと search_form_for で ArgumentError になるため必須
    base_customers = current_client.customers
                                   .includes(:last_form_call)
                                   .left_joins(:calls)
                                   .distinct
    @q = base_customers.ransack(params[:q])
    filtered = @q.result

    # 送信画面の表示に必要な変数群
    @customers = filtered
                   .where.not(contact_url: [nil, '', 'not_detected'])
                   .page(params[:customers_page]).per(20)

    @detectable_customers = filtered
                              .where(contact_url: [nil, ''])
                              .where.not(url: [nil, ''])
                              .where(fobbiden: [nil, false, 0])
                              .page(params[:detectable_page]).per(20)

    @not_detected_count = current_client.customers.where(contact_url: 'not_detected').count
    @no_url_customers_count = current_client.customers
                                            .where(contact_url: [nil, ''])
                                            .where(url: [nil, ''])
                                            .count
    @submissions = current_client.submissions.order(created_at: :desc)
  end

  def searching_form
    # -------------------------
    # 自分の顧客のみ
    # -------------------------
    base_customers = current_client.customers
                                   .includes(:last_form_call)
                                   .left_joins(:calls)
                                   .distinct

    # -------------------------
    # 検索（Ransack）
    # -------------------------
    @q = base_customers.ransack(params[:q])
    filtered = @q.result

    # -------------------------
    # 自動検出対象 (@detectable_customers.any? 用)
    # -------------------------
    @detectable_customers = filtered
                              .where(contact_url: [nil, ''])
                              .where.not(url: [nil, ''])
                              .where(fobbiden: [nil, false, 0])
                              .page(params[:detectable_page]).per(50)

    # -------------------------
    # カウント系 (nilエラー解消用)
    # -------------------------
    # 検出失敗済み
    @not_detected_count = current_client.customers.where(contact_url: 'not_detected').count

    # URL自体が未設定 (@no_url_customers_count > 0 用)
    @no_url_customers_count = current_client.customers
                                            .where(contact_url: [nil, ''])
                                            .where(url: [nil, ''])
                                            .count
  end

  def setting
  end
end

  def history
    # ---------------------------------------------------------
    # 履歴ページ（_history.html.slim）で必要な変数を定義
    # ---------------------------------------------------------
    @q = current_client.customers.ransack(params[:q])
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
    # 検索オブジェクト @q がないと search_form_for で ArgumentError になるため必須
    base_customers = current_client.customers
                                   .includes(:last_form_call)
                                   .left_joins(:calls)
                                   .distinct
    @q = base_customers.ransack(params[:q])
    filtered = @q.result

    # 送信画面の表示に必要な変数群
    @customers = filtered
                   .where.not(contact_url: [nil, '', 'not_detected'])
                   .page(params[:customers_page]).per(20)

    @detectable_customers = filtered
                              .where(contact_url: [nil, ''])
                              .where.not(url: [nil, ''])
                              .where(fobbiden: [nil, false, 0])
                              .page(params[:detectable_page]).per(20)

    @not_detected_count = current_client.customers.where(contact_url: 'not_detected').count
    @no_url_customers_count = current_client.customers
                                            .where(contact_url: [nil, ''])
                                            .where(url: [nil, ''])
                                            .count
    @submissions = current_client.submissions.order(created_at: :desc)
  end

  def searching_form
    # -------------------------
    # 自分の顧客のみ
    # -------------------------
    base_customers = current_client.customers
                                   .includes(:last_form_call)
                                   .left_joins(:calls)
                                   .distinct

    # -------------------------
    # 検索（Ransack）
    # -------------------------
    @q = base_customers.ransack(params[:q])
    filtered = @q.result

    # -------------------------
    # 自動検出対象 (@detectable_customers.any? 用)
    # -------------------------
    @detectable_customers = filtered
                              .where(contact_url: [nil, ''])
                              .where.not(url: [nil, ''])
                              .where(fobbiden: [nil, false, 0])
                              .page(params[:detectable_page]).per(50)

    # -------------------------
    # カウント系 (nilエラー解消用)
    # -------------------------
    # 検出失敗済み
    @not_detected_count = current_client.customers.where(contact_url: 'not_detected').count

    # URL自体が未設定 (@no_url_customers_count > 0 用)
    @no_url_customers_count = current_client.customers
                                            .where(contact_url: [nil, ''])
                                            .where(url: [nil, ''])
                                            .count
  end

  def setting
  end
end