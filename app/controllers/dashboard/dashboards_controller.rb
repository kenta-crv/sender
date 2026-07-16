class Dashboard::DashboardsController < ApplicationController
  skip_before_action :check_trial_expiration

  before_action :authenticate_any!
  before_action :require_admin!, only: [:management, :funnel_tracking]
  before_action :check_subscription_active!, unless: :admin_signed_in?
  before_action :set_base_scope, except: [:index, :setting, :management, :funnel_tracking, :click_tracking, :howto]

  def index
    insights_scope = customer_insights_scope

    @total_customers_count = Customer.unscoped.where.not(contact_url: [nil, '', 'not_detected']).count
    @not_detected_count = insights_scope.where(contact_url: 'not_detected').count
    @no_url_customers_count = insights_scope.where(contact_url: [nil, '']).where(url: [nil, '']).count

    notification_scope = if admin_signed_in?
      Notification.all
    elsif client_signed_in?
      Notification.for_client(current_client.id)
    else
      Notification.none
    end

    @unread_notification_count = notification_scope.unread.count

    batch_scope = form_batch_scope
    @batches = batch_scope
              .includes(:submission, :client, :admin)
              .order(created_at: :desc)
              .limit(3)

    current_month_range = Time.current.beginning_of_month..Time.current.end_of_month
    monthly_scope = batch_scope.where(created_at: current_month_range)
    @total_sent, @total_success, @total_failure = monthly_scope.pick(
      Arel.sql('COALESCE(SUM(total_count), 0)'),
      Arel.sql('COALESCE(SUM(success_count), 0)'),
      Arel.sql('COALESCE(SUM(failure_count), 0)')
    )
    @total_sent = @total_sent.to_i
    @total_success = @total_success.to_i
    @total_failure = @total_failure.to_i

    @success_rate =
      @total_sent.positive? ? ((@total_success.to_f / @total_sent) * 100).round(1) : 0

    @submission_stats = build_submission_stats(batch_scope)

    if admin_signed_in? && params[:client_id].present?
      assign_monthly_usage_stats!(Client.find(params[:client_id]))
    elsif client_signed_in?
      assign_monthly_usage_stats!(current_client)
    elsif admin_signed_in?
      assign_monthly_usage_stats_for_admin!
    else
      assign_monthly_usage_stats_empty!
    end

    click_scope = click_tracking_scope.where(created_at: current_month_range)

    @total_clicks = click_scope.sum(:clicked_count).to_i

    @clicked_users_count = click_scope
      .where.not(clicked_count: nil)
      .where("clicked_count > 0")
      .where.not(last_clicked_at: nil)
      .where("last_clicked_at <= ?", Time.current)
      .count

    @click_rate =
      @total_success.positive? ? ((@clicked_users_count.to_f / @total_success) * 100).round(1) : 0
  end

  def history
    @q = @base_customers.ransack(params[:q])

    if admin_signed_in?
      if params[:client_id].present?
        @batches = FormSubmissionBatch.where(client_id: params[:client_id]).order(created_at: :desc).page(params[:page]).per(20)
        @submissions = Submission.where(client_id: params[:client_id]).order(created_at: :desc)
      else
        @batches = FormSubmissionBatch.order(created_at: :desc).page(params[:page]).per(20)
        @submissions = Submission.order(created_at: :desc)
      end
    elsif client_signed_in?
      @batches = current_client.form_submission_batches.order(created_at: :desc).page(params[:page]).per(20)
      @submissions = current_client.submissions.order(created_at: :desc)
    else
      @batches = FormSubmissionBatch.none
      @submissions = Submission.none
    end

    @submission_stats = @submissions.map do |submission|
      batches = submission.form_submission_batches
      batches = batches.where(client_id: current_client.id) if client_signed_in? && !admin_signed_in?

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

    if admin_signed_in? && params[:last_call].present?
      lc = params[:last_call]
      statuses = Array(lc[:status]).reject(&:blank?)
      from_date = lc[:created_at_from].presence
      to_date = lc[:created_at_to].presence
      unsent = lc[:calls_id_null].to_s == 'true'
      has_sent_filters = statuses.any? || from_date.present? || to_date.present?

      if unsent || has_sent_filters
        filtered_ids = filtered.includes(:last_form_call).select do |customer|
          call = customer.last_form_call
          next unsent if call.blank?
          next false unless has_sent_filters

          status_ok = statuses.blank? || statuses.include?(call.status)
          from_ok = from_date.blank? || call.created_at >= Time.zone.parse(from_date)
          to_ok = to_date.blank? || call.created_at <= Time.zone.parse(to_date).end_of_day

          status_ok && from_ok && to_ok
        end.map(&:id)

        filtered = filtered.where(id: filtered_ids)
      end
    end

    excluded_statuses = ['フォーム未検出', 'アクセス失敗', 'エラー', 'not_detected', 'CAPTCHA NG']

    @customers = filtered
                   .where.not(contact_url: [nil, '', 'not_detected'])
                   .left_joins(:calls)
                   .where("calls.status NOT IN (?) OR calls.id IS NULL", excluded_statuses)
                   .page(params[:customers_page]).per(50)

    @detectable_customers = filtered
                              .where(contact_url: [nil, ''])
                              .where.not(url: [nil, ''])
                              .with_legal_entity
                              .deliverable_for(delivery_filter_client_id)
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

    if admin_signed_in?
      @submissions = Submission.where(client_id: nil).order(created_at: :desc)
    elsif client_signed_in?
      @submissions = current_client.submissions.order(created_at: :desc)
    else
      @submissions = Submission.none
    end
  end

def searching_form
  @q = @base_customers.ransack(params[:q])
  filtered = @q.result(distinct: true)

  if params[:business_filter].present?
    filtered = filtered.where(business: params[:business_filter])
  end

  if params[:genre_filter].present?
    filtered = filtered.where(genre: params[:genre_filter])
  end

  @detectable_customers = filtered
                            .where(contact_url: [nil, ''])
                            .where.not(url: [nil, ''])
                            .with_legal_entity
                            .deliverable_for(delivery_filter_client_id)
                            .page(params[:detectable_page]).per(50)

  @not_detected_count = @base_customers.where(contact_url: 'not_detected').count
  @no_url_customers_count = @base_customers.where(contact_url: [nil, '']).where(url: [nil, '']).count

  detectable_base = @q.result(distinct: true)
                      .where(contact_url: [nil, ''])
                      .where.not(url: [nil, ''])
                      .with_legal_entity
                      .deliverable_for(delivery_filter_client_id)

  @business_options = detectable_base.where.not(business: [nil, ''])
                                     .group(:business)
                                     .count
                                     .select { |_name, count| count >= 1 }
                                     .sort_by { |_name, count| -count }
                                     .map { |name, count| ["#{name}（#{count}件）", name] }

  @genre_options = detectable_base.where.not(genre: [nil, ''])
                                  .group(:genre)
                                  .count
                                  .select { |_name, count| count >= 1 }
                                  .sort_by { |_name, count| -count }
                                  .map { |name, count| ["#{name}（#{count}件）", name] }

  @submissions = admin_signed_in? ? Submission.where(client_id: nil).order(created_at: :desc) : (client_signed_in? ? current_client.submissions.order(created_at: :desc) : Submission.none)
end

  def setting; end

  def management
    start_of_month = Time.current.beginning_of_month
    end_of_month   = Time.current.end_of_month

    @clients = Client.select(
                       'clients.*',
                       "(SELECT sent_count FROM monthly_usage_logs WHERE monthly_usage_logs.client_id = clients.id AND monthly_usage_logs.created_at BETWEEN '#{start_of_month.to_s(:db)}' AND '#{end_of_month.to_s(:db)}' ORDER BY monthly_usage_logs.id DESC LIMIT 1) AS current_month_sends"
                     )
                     .includes(:subscriptions)
                     .order(created_at: :desc)
  end

  def howto; end

  def funnel_tracking
    unless ActiveRecord::Base.connection.data_source_exists?('funnel_events')
      redirect_to dashboard_index_path, alert: 'ファネル分析を利用するには db:migrate の実行が必要です。'
      return
    end

    since = params[:since].present? ? params[:since].to_i.days.ago : 30.days.ago

    raw = FunnelEvent.where(created_at: since..)
                     .group(:page, :event_type)
                     .count

    @pages = FunnelEvent::PAGES
    @since_days = params[:since].present? ? params[:since].to_i : 30

    @stats = @pages.each_with_object({}) do |page, h|
      h[page] = {
        visit:   raw[[page, 'visit']].to_i,
        abandon: raw[[page, 'abandon']].to_i,
        proceed: raw[[page, 'proceed']].to_i
      }
    end

    detail_scope = FunnelEvent.where(created_at: since..).recent
    if FunnelEvent.column_names.include?('click_tracking_link_id')
      detail_scope = detail_scope.includes(click_tracking_link: [:customer, :submission])
    end

    @filter_page  = params[:filter_page].presence
    @filter_event = params[:filter_event].presence

    if @filter_page.present? && FunnelEvent::PAGES.include?(@filter_page)
      detail_scope = detail_scope.where(page: @filter_page)
    end
    if @filter_event.present? && FunnelEvent::EVENT_TYPES.include?(@filter_event)
      detail_scope = detail_scope.where(event_type: @filter_event)
    end

    @recent_events = detail_scope.limit(100)

    @stripe_expired_count = FunnelEvent.where(
      page: 'stripe_session_expired',
      created_at: since..
    ).count
  end

  def click_tracking
    click_scope =
      if admin_signed_in?
        if params[:client_id].present?
          ClickTrackingLink.where(client_id: params[:client_id])
        else
          ClickTrackingLink.all
        end
      elsif client_signed_in?
        ClickTrackingLink.where(client_id: current_client.id)
      else
        ClickTrackingLink.none
      end

    click_scope = click_scope.where(submission_id: params[:submission_id]) if params[:submission_id].present?

    @filter_submissions =
      if admin_signed_in?
        if params[:client_id].present?
          Submission.where(client_id: params[:client_id]).order(created_at: :desc)
        else
          Submission.order(created_at: :desc)
        end
      elsif client_signed_in?
        current_client.submissions.order(created_at: :desc)
      else
        Submission.none
      end

    @clicked_links = click_scope.where.not(clicked_count: nil)
                                .where("clicked_count > 0")
                                .includes(:customer, :click_logs, :submission, :form_submission_batch)
                                .order(last_clicked_at: :desc)
                                .page(params[:page])
                                .per(20)
  end

  private

  def assign_monthly_usage_stats!(client)
    monthly_log = client.monthly_usage_log
    limits = client.usage_limits
    @serp_api_used = monthly_log.serp_api_used
    @form_detection_used = monthly_log.form_detection_used
    @serp_api_limit = limits[:serp_api_limit]
    @form_detection_limit = limits[:form_detection_limit]
    @usage_unlimited = false
    @import_count = monthly_import_count_for(client.id)
  end

  def assign_monthly_usage_stats_for_admin!
    month_key = Time.current.strftime('%Y-%m')
    logs = MonthlyUsageLog.where(month: month_key)
    @serp_api_used = logs.sum(:serp_api_used)
    @form_detection_used = logs.sum(:form_detection_used)
    @serp_api_limit = nil
    @form_detection_limit = nil
    @usage_unlimited = true
    @import_count = monthly_import_count_for(nil)
  end

  def assign_monthly_usage_stats_empty!
    @serp_api_limit = 0
    @serp_api_used = 0
    @form_detection_limit = 0
    @form_detection_used = 0
    @usage_unlimited = false
    @import_count = 0
  end

  def monthly_import_count_for(client_id)
    scope = Notification.where(
      type: 'CustomerImport',
      created_at: Time.current.beginning_of_month..Time.current.end_of_month
    )
    scope = scope.where(client_id: client_id) if client_id.present?
    scope.sum(:success_count)
  end

  def customer_insights_scope
    if admin_signed_in? && params[:client_id].present?
      Customer.where(client_id: params[:client_id])
    elsif admin_signed_in?
      Customer.all
    elsif client_signed_in?
      Customer.where(client_id: current_client.id)
    else
      Customer.none
    end
  end

  def form_batch_scope
    if admin_signed_in? && params[:client_id].present?
      FormSubmissionBatch.where(client_id: params[:client_id])
    elsif admin_signed_in?
      FormSubmissionBatch.all
    elsif client_signed_in?
      current_client.form_submission_batches
    else
      FormSubmissionBatch.none
    end
  end

  def click_tracking_scope
    if admin_signed_in? && params[:client_id].present?
      ClickTrackingLink.where(client_id: params[:client_id])
    elsif admin_signed_in?
      ClickTrackingLink.all
    elsif client_signed_in?
      ClickTrackingLink.where(client_id: current_client.id)
    else
      ClickTrackingLink.none
    end
  end

  def dashboard_submissions_scope
    if admin_signed_in? && params[:client_id].present?
      Submission.where(client_id: params[:client_id]).order(created_at: :desc)
    elsif admin_signed_in?
      Submission.order(created_at: :desc)
    elsif client_signed_in?
      current_client.submissions.order(created_at: :desc)
    else
      Submission.none
    end
  end

  def build_submission_stats(batch_scope)
    submissions = dashboard_submissions_scope.to_a
    return [] if submissions.empty?

    stats_rows = batch_scope
      .where.not(submission_id: nil)
      .group(:submission_id)
      .pluck(
        :submission_id,
        Arel.sql('COALESCE(SUM(total_count), 0)'),
        Arel.sql('COALESCE(SUM(success_count), 0)'),
        Arel.sql('COALESCE(SUM(failure_count), 0)')
      )

    stats_by_submission = stats_rows.each_with_object({}) do |(submission_id, total, success, failure), memo|
      memo[submission_id] = {
        total_sent: total.to_i,
        success_count: success.to_i,
        failure_count: failure.to_i
      }
    end

    sender_batch_ids = batch_scope
      .where.not(submission_id: nil)
      .group(:submission_id)
      .minimum(:id)

    sender_batches =
      if sender_batch_ids.empty?
        {}
      else
        FormSubmissionBatch
          .where(id: sender_batch_ids.values)
          .includes(:client, :admin)
          .index_by(&:submission_id)
      end

    submissions.map do |submission|
      stats = stats_by_submission[submission.id] || { total_sent: 0, success_count: 0, failure_count: 0 }
      sender_batch = sender_batches[submission.id]

      stats.merge(
        submission: submission,
        sender_client: sender_batch&.client,
        sender_admin: sender_batch&.admin
      )
    end
  end

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
    elsif client_signed_in?
      @base_customers = Customer.where(client_id: current_client.id).includes(:last_form_call).left_joins(:calls).distinct
    else
      @base_customers = Customer.none
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