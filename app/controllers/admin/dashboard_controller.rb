class Admin::DashboardController < ApplicationController
  before_action :authenticate_admin!

  def index
    # -------------------------
    # 全顧客（Adminは所有しない）
    # -------------------------
    base_customers = Customer
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
    @not_detected_count = Customer.where(contact_url: 'not_detected').count

    @no_url_customers_count = Customer
                                .where(contact_url: [nil, ''])
                                .where(url: [nil, ''])
                                .count

    # -------------------------
    # Submission（全体）
    # -------------------------
    @submissions = Submission.order(created_at: :desc)

    # -------------------------
    # Batch（全体）
    # -------------------------
    @batches = FormSubmissionBatch
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
    @active_jobs = @batches.where(status: 'processing').count
  end

  def history
  end

  def setting
    @admin = current_admin
  end
end