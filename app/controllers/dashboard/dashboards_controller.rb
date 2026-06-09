class Dashboard::DashboardsController < ApplicationController
  skip_before_action :check_trial_expiration

  before_action :authenticate_any!
  before_action :require_admin!, only: [:management]
  before_action :check_subscription_active!, unless: :admin_signed_in?
  before_action :set_base_scope, except: [:setting, :management]

def index
  # 「送信可能顧客（contact_url有）」についてのみ、現在のログインClientに縛られず、
  # システム全体の Customer から重複なし・クリーンな状態で全件数を強制取得
  @total_customers_count = Customer.unscoped.where.not(contact_url: [nil, '', 'not_detected']).count

  # その他の項目（フォーム未検出、URL未設定）については、ログイン中のベーススコープ（既存の絞り込み仕様）を維持しつつ、
  # left_joins による集計バグを回避するため unscope(:joins) を適用して安全にカウント
  @not_detected_count = @base_customers.unscope(:joins).where(contact_url: 'not_detected').count
  @no_url_customers_count = @base_customers.unscope(:joins).where(contact_url: [nil, '']).where(url: [nil, '']).count

  # 画面描画用・検索用の既存ロジック（そのまま維持します）
  @q = @base_customers.ransack(params[:q])
  filtered = @q.result(distinct: true)

  @customers = filtered.where.not(contact_url: [nil, '', 'not_detected']).page(params[:customers_page]).per(20)
  @detectable_customers = filtered.where(contact_url: [nil, '']).where.not(url: [nil, '']).where(fobbiden: [nil, false, 0]).page(params[:detectable_page]).per(20)

  @business_options = generate_options(:business)
  @genre_options = generate_options(:genre)

  if client_signed_in?
    @submissions = current_client.submissions.order(created_at: :desc)
    @batches = current_client.form_submission_batches.order(created_at: :desc).page(params[:page]).per(10)
  elsif admin_signed_in?
    if params[:client_id].present?
      @submissions = Submission.where(client_id: params[:client_id]).order(created_at: :desc)
      @batches = FormSubmissionBatch.where(client_id: params[:client_id]).order(created_at: :desc).page(params[:page]).per(10)
    else
      @submissions = Submission.order(created_at: :desc)
      @batches = FormSubmissionBatch.order(created_at: :desc).page(params[:page]).per(10)
    end
  else
    @submissions = Submission.none
    @batches = FormSubmissionBatch.none
  end

  current_month_range = Time.current.beginning_of_month..Time.current.end_of_month

  scope =
    if client_signed_in?
      current_client.form_submission_batches
    elsif admin_signed_in? && params[:client_id].present?
      FormSubmissionBatch.where(client_id: params[:client_id])
    else
      FormSubmissionBatch.all
    end

  @monthly_batches = scope.where(created_at: current_month_range)

  @total_sent = @monthly_batches.sum(:total_count)
  @total_success = @monthly_batches.sum(:success_count)
  @total_failure = @monthly_batches.sum(:failure_count)

  @success_rate =
    @total_sent.positive? ? ((@total_success.to_f / @total_sent) * 100).round(1) : 0

  click_scope =
    if client_signed_in?
      ClickTrackingLink.where(client_id: current_client.id)
    elsif admin_signed_in? && params[:client_id].present?
      ClickTrackingLink.where(client_id: params[:client_id])
    else
      ClickTrackingLink.all
    end

  click_scope = click_scope.where(created_at: current_month_range)

  @total_clicks = click_scope.sum(:clicked_count).to_i

  @clicked_users_count = click_scope
    .where.not(clicked_count: nil)
    .where("clicked_count > 0")
    .where.not(last_clicked_at: nil)
    .where("last_clicked_at <= ?", Time.current)
    .count

  # クリックレートの分母を送信総数(@total_sent)から送信成功数(@total_success)に変更
  @click_rate =
    @total_success.positive? ? ((@clicked_users_count.to_f / @total_success) * 100).round(1) : 0
end
  
  def history
    @q = @base_customers.ransack(params[:q])

    if client_signed_in?
      @batches = current_client.form_submission_batches.order(created_at: :desc).page(params[:page]).per(20)
      @submissions = current_client.submissions.order(created_at: :desc)
    elsif admin_signed_in?
      if params[:client_id].present?
        @batches = FormSubmissionBatch.where(client_id: params[:client_id]).order(created_at: :desc).page(params[:page]).per(20)
        @submissions = Submission.where(client_id: params[:client_id]).order(created_at: :desc)
      else
        @batches = FormSubmissionBatch.order(created_at: :desc).page(params[:page]).per(20)
        @submissions = Submission.order(created_at: :desc)
      end
    else
      @batches = FormSubmissionBatch.none
      @submissions = Submission.none
    end

    @submission_stats = @submissions.map do |submission|
      batches = submission.form_submission_batches
      batches = batches.where(client_id: current_client.id) if client_signed_in?

      {
        submission: submission,
        total_sent: batches.sum(:total_count),
        success_count: batches.sum(:success_count),
        failure_count: batches.sum(:failure_count),
        last_sent_at: batches.order(started_at: :desc).pluck(:started_at).first
      }
    end
  end

  def sending
    @base_customers = Customer.all

    @q = @base_customers.includes(:last_form_call).ransack(params[:q])
    filtered = @q.result(distinct: true)

    excluded_statuses = ['フォーム未検出', 'アクセス失敗', 'エラー', 'not_detected']

    @customers = filtered
                   .where.not(contact_url: [nil, '', 'not_detected'])
                   .left_joins(:calls)
                   .where("calls.status NOT IN (?) OR calls.id IS NULL", excluded_statuses)
                   .page(params[:customers_page]).per(50)

    @detectable_customers = filtered
                              .where(contact_url: [nil, ''])
                              .where.not(url: [nil, ''])
                              .where(fobbiden: [nil, false, 0])
                              .page(params[:detectable_page]).per(50)

    @business_options = generate_options(:business)
    @genre_options = generate_options(:genre)

    @customers_count = @customers.total_count
    @detectable_count = @detectable_customers.total_count

    query_scope = @base_customers.left_joins(:calls)
    @not_detected_count = query_scope
                            .where(contact_url: 'not_detected')
                            .or(query_scope.where(calls: { status: excluded_statuses }))
                            .distinct.count

    if client_signed_in?
      @submissions = current_client.submissions.order(created_at: :desc)
    else
      @submissions = Submission.order(created_at: :desc)
    end
  end

  def searching_form
    @q = @base_customers.ransack(params[:q])
    filtered = @q.result(distinct: true)

    @detectable_customers = filtered
                              .where(contact_url: [nil, ''])
                              .where.not(url: [nil, ''])
                              .where(fobbiden: [nil, false, 0])
                              .page(params[:detectable_page]).per(50)

    @not_detected_count = @base_customers.where(contact_url: 'not_detected').count
    @no_url_customers_count = @base_customers.where(contact_url: [nil, '']).where(url: [nil, '']).count

    @submissions = client_signed_in? ? current_client.submissions.order(created_at: :desc) : Submission.none
  end

  def setting; end

def management
    start_of_month = Time.current.beginning_of_month
    end_of_month   = Time.current.end_of_month

    # 各Clientに完全に1対1で紐づく、monthly_usage_logsの最新のsent_countをピンポイントで取得します。
    # サブクエリ形式にすることで、結合によるデータの重複や他クライアントとの数値の混ざりを完全に防ぎます。
    @clients = Client.select(
                       'clients.*',
                       "(SELECT sent_count FROM monthly_usage_logs WHERE monthly_usage_logs.client_id = clients.id AND monthly_usage_logs.created_at BETWEEN '#{start_of_month.to_s(:db)}' AND '#{end_of_month.to_s(:db)}' ORDER BY monthly_usage_logs.id DESC LIMIT 1) AS current_month_sends"
                     )
                     .includes(:subscriptions)
                     .order(created_at: :desc)
  end

  def howto; end

  private

  def authenticate_any!
    redirect_to root_path unless admin_signed_in? || client_signed_in?
  end

  def require_admin!
    redirect_to root_path, alert: "このページへのアクセス権限がありません。" unless admin_signed_in?
  end

  def check_subscription_active!
    return unless client_signed_in?

    plan = current_client.subscription_plan
    status = current_client.subscription_status

    if plan == 'none' || plan.blank? || status == 'cancelled'
      latest_sub = current_client.subscriptions.order(created_at: :desc).first

      if latest_sub.present? && latest_sub.stripe_subscription_id.present?
        begin
          stripe_sub = Stripe::Subscription.retrieve(latest_sub.stripe_subscription_id)
          period_end = stripe_sub.respond_to?(:current_period_end) ? stripe_sub.current_period_end : stripe_sub.items&.data&.first&.current_period_end

          if period_end && Time.at(period_end).past?
            redirect_to dashboard_subscription_path, alert: "サブスクリプションの有効期限が終了しています。再度ご契約ください。"
            return
          end
        rescue Stripe::StripeError
          redirect_to dashboard_subscription_path, alert: "サブスクリプションの確認ができません。プランを再確認してください。"
          return
        end
      else
        redirect_to dashboard_subscription_path, alert: "サービスをご利用いただくには、プランへの加入が必要です。"
      end
    end
  end

  def set_base_scope
    if admin_signed_in?
      if params[:client_id].present?
        @base_customers = Customer.where(client_id: params[:client_id]).includes(:last_form_call).left_joins(:calls).distinct
      else
        @base_customers = Customer.all.includes(:last_form_call).left_joins(:calls).distinct
      end
    else
      @base_customers = Customer.where(client_id: current_client.id).includes(:last_form_call).left_joins(:calls).distinct
    end
  end

  def generate_options(column)
    @base_customers.where.not(column => [nil, ''])
                   .group(column).count
                   .select { |_name, count| count >= 30 }
                   .sort_by { |_name, count| -count }
                   .map { |name, count| ["#{name}（#{count}件）", name] }
  end
end