class SubmissionsController < ApplicationController
  before_action :authenticate_admin_or_client!
  before_action :set_submission, only: [:show, :edit, :update, :destroy, :manual, :history]
  before_action :authenticate_admin!
  # =========================
  # 一覧
  # =========================
  def index
    @customers = scoped_customers.where.not(contact_url: [nil, ""])

    @detectable_customers = scoped_customers
                              .where(contact_url: [nil, ""])
                              .where.not(url: [nil, ""])

    @no_url_customers_count = scoped_customers
                                .where(contact_url: [nil, ""], url: [nil, ""])
                                .count

    @submissions = scoped_submissions

    @batches = scoped_batches
                 .includes(:submission)
                 .order(created_at: :desc)
                 .page(params[:page])
                 .per(10)
  end

  def show
  end

  # =========================
  # 新規作成
  # =========================
  def new
    @submission = build_submission
  end

  def create
    @submission = build_submission(submission_params)

    if @submission.save
      redirect_to submissions_path, notice: '送信内容を作成しました。'
    else
      render :new
    end
  end

  # =========================
  # 編集
  # =========================
  def edit
  end

  def update
    if @submission.update(submission_params)
      redirect_to submissions_path, notice: '送信内容を更新しました。'
    else
      render :edit
    end
  end

  # =========================
  # 削除
  # =========================
  def destroy
    @submission.destroy
    redirect_to submissions_path, notice: '送信内容を削除しました。'
  end

  # =========================
  # 手動送信対象
  # =========================
  def manual
    customers_scope = scoped_customers
                        .where(contact_url: [nil, ''], url: [nil, ''], fobbiden: [nil, false, 0])

    @display_rows = []
    seen_customer_ids = Set.new

    latest_calls = Call.where(customer_id: customers_scope.pluck(:id))
                       .order(created_at: :desc)
                       .group_by(&:customer_id)

    customers_scope.each do |customer|
      next if seen_customer_ids.include?(customer.id)

      call = latest_calls[customer.id]&.first
      next if call.present?

      @display_rows << {
        customer: customer,
        latest_call: nil,
        status_text: 'URL未設定',
        batch_at: customer.created_at
      }

      seen_customer_ids << customer.id
    end

    @all_target_ids = @display_rows.map { |row| row[:customer].id }
  end

  # =========================
  # 履歴
  # =========================
  def history
    batches = @submission.form_submission_batches
                         .merge(scoped_batches) # ← ここが重要（client制御）

    @display_rows = []
    seen_customer_ids = Set.new

    batches.order(created_at: :desc).each do |batch|
      customer_ids = batch.customer_ids.present? ? JSON.parse(batch.customer_ids) : []
      error_logs   = batch.error_log.present? ? JSON.parse(batch.error_log) : []

      customers = scoped_customers
                    .where(id: customer_ids, fobbiden: nil)
                    .index_by(&:id)

      latest_calls = Call.where(customer_id: customer_ids)
                         .order(created_at: :desc)
                         .group_by(&:customer_id)

      customer_ids.each do |c_id|
        next if seen_customer_ids.include?(c_id)

        customer = customers[c_id]
        next unless customer

        call  = latest_calls[c_id]&.first
        error = error_logs.find { |e| e["customer_id"] == c_id }

        status_text =
          if call.present?
            call.status
          elsif error.present?
            '自動送信失敗'
          else
            '自動送信成功'
          end

        if ['自動送信失敗', 'フォーム未検出'].include?(status_text)
          @display_rows << {
            customer: customer,
            latest_call: call,
            error_entry: error,
            status_text: status_text,
            batch_at: batch.created_at
          }

          seen_customer_ids << c_id
        end
      end
    end

    @all_target_ids = @display_rows.map { |row| row[:customer].id }
  end

  private

  # =========================
  # 認証
  # =========================
  def authenticate_admin_or_client!
    unless admin_signed_in? || client_signed_in?
      redirect_to root_path, alert: 'ログインしてください'
    end
  end

  # =========================
  # スコープ系（最重要）
  # =========================
  def scoped_customers
    if admin_signed_in?
      Customer.all
    else
      Customer.where(client_id: current_client.id)
    end
  end

  def scoped_submissions
    if admin_signed_in?
      Submission.all
    else
      Submission.where(client_id: current_client.id)
    end
  end

  def scoped_batches
    if admin_signed_in?
      FormSubmissionBatch.all
    else
      FormSubmissionBatch.where(client_id: current_client.id)
    end
  end

  # =========================
  # build系
  # =========================
  def build_submission(params = {})
    if admin_signed_in?
      Submission.new(params)
    else
      current_client.submissions.new(params)
    end
  end

  # =========================
  # find
  # =========================
  def set_submission
    @submission = scoped_submissions.find(params[:id])
  end

  # =========================
  # strong params
  # =========================
  def submission_params
    params.require(:submission).permit(
      :headline, :company, :person, :person_kana,
      :tel, :fax, :address, :email, :url,
      :title, :content, :manual
    )
  end
end