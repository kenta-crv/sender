class SubmissionsController < ApplicationController
  before_action :set_submission, only: [:show, :edit, :update, :destroy]

  def index
    @customers = Customer.where.not(contact_url: [nil, ""])
    @detectable_customers = Customer.where(contact_url: [nil, ""]).where.not(url: [nil, ""])
    @no_url_customers_count = Customer.where(contact_url: [nil, ""], url: [nil, ""]).count
    @submissions = Submission.all
    @batches = FormSubmissionBatch.includes(:submission).order(created_at: :desc).page(params[:page]).per(10)
  end

  def show
  end

  def new
    @submission = Submission.new
  end

  def create
    @submission = Submission.new(submission_params)
    if @submission.save
      redirect_to submissions_path, notice: '送信内容を作成しました。'
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @submission.update(submission_params)
      redirect_to submissions_path, notice: '送信内容を更新しました。'
    else
      render :edit
    end
  end

  def destroy
    @submission.destroy
    redirect_to submissions_path, notice: '送信内容を削除しました。'
  end

def manual
  customers_scope = Customer.where(contact_url: [nil, ''], url: [nil, ''], fobbiden: [nil, false, 0])

  @display_rows = []
  seen_customer_ids = Set.new

  latest_calls = Call.where(customer_id: customers_scope.pluck(:id)).order(created_at: :desc).group_by(&:customer_id)

  customers_scope.each do |customer|
    next if seen_customer_ids.include?(customer.id)

    call = latest_calls[customer.id]&.first
    # call が存在するものは除外
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
  @submission = Submission.find(params[:id])
end
def history
  @submission = Submission.find(params[:id])
  # 新しいバッチから順に取得
  batches = @submission.form_submission_batches.order(created_at: :desc)
  
  @display_rows = []
  seen_customer_ids = Set.new # 重複表示を防ぐため

  batches.each do |batch|
    customer_ids = batch.customer_ids.present? ? JSON.parse(batch.customer_ids) : []
    error_logs = batch.error_log.present? ? JSON.parse(batch.error_log) : []
    
    # 絞り込み条件: fobbiden が nil の顧客のみ
    customers = Customer.where(id: customer_ids, fobbiden: nil).index_by(&:id)
    # 顧客ごとの最新の架電・送信ステータスを取得
    latest_calls = Call.where(customer_id: customer_ids).order(created_at: :desc).group_by(&:customer_id)

    customer_ids.each do |c_id|
      # すでにリストに追加済みの顧客、または送信禁止の顧客はスキップ
      next if seen_customer_ids.include?(c_id)
      customer = customers[c_id]
      next unless customer

      call = latest_calls[c_id]&.first
      error = error_logs.find { |e| e["customer_id"] == c_id }

      # ステータス判定の優先順位: 1.Callレコード 2.エラーログ 3.デフォルト成功
      status_text = if call.present?
                      call.status
                    elsif error.present?
                      '自動送信失敗'
                    else
                      '自動送信成功'
                    end

      # 【修正ポイント】表示対象を「自動送信失敗」と「フォーム未検出」に限定
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

  # 詳細画面への遷移用などにIDリストを保持
  @all_target_ids = @display_rows.map { |row| row[:customer].id }
end

  private

  def set_submission
    @submission = Submission.find(params[:id])
  end

  def submission_params
    params.require(:submission).permit(
      :headline, :company, :person, :person_kana,
      :tel, :fax, :address, :email, :url, :title, :content
    )
  end
end
