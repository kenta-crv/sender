class Dashboard::DashboardsController < ApplicationController
  skip_before_action :check_trial_expiration

  before_action :authenticate_any!
  before_action :require_admin!, only: [:management, :funnel_tracking]
  before_action :check_subscription_active!, unless: :admin_signed_in?
  before_action :set_base_scope, except: [:setting, :management]

  def index
    @total_customers_count = Customer.unscoped.where.not(contact_url: [nil, '', 'not_detected']).count

    @not_detected_count = @base_customers.unscope(:joins).where(contact_url: 'not_detected').count
    @no_url_customers_count = @base_customers.unscope(:joins).where(contact_url: [nil, '']).where(url: [nil, '']).count

    @q = @base_customers.ransack(params[:q])
    filtered = @q.result(distinct: true)

    @customers = filtered.where.not(contact_url: [nil, '', 'not_detected']).page(params[:customers_page]).per(20)
    @detectable_customers = filtered.where(contact_url: [nil, '']).where.not(url: [nil, '']).with_legal_entity.deliverable_for(delivery_filter_client_id).page(params[:detectable_page]).per(20)

    @business_options = generate_options(:business)
    @genre_options = generate_options(:genre)

    # Notification data
    notification_scope = if admin_signed_in?
      Notification.all
    elsif client_signed_in?
      Notification.for_client(current_client.id)
    else
      Notification.none
    end

    @unread_notifications = notification_scope.unread.recent.limit(5)
    @unread_notification_count = notification_scope.unread.count

    if admin_signed_in?
      if params[:client_id].present?
        client = Client.find(params[:client_id])
        @submissions = client.submissions.order(created_at: :desc)
        @batches = client.form_submission_batches.order(created_at: :desc).page(params[:page]).per(10)
      else
        @submissions = Submission.all.order(created_at: :desc)
        @batches = FormSubmissionBatch.all.order(created_at: :desc).page(params[:page]).per(10)
      end
    elsif client_signed_in?
      @submissions = current_client.submissions.order(created_at: :desc)
      @batches = current_client.form_submission_batches.order(created_at: :desc).page(params[:page]).per(10)
    else
      @submissions = Submission.none
      @batches = FormSubmissionBatch.none
    end

    current_month_range = Time.current.beginning_of_month..Time.current.end_of_month

    scope =
      if admin_signed_in? && params[:client_id].present?
        FormSubmissionBatch.where(client_id: params[:client_id])
      elsif admin_signed_in?
        FormSubmissionBatch.all
      elsif client_signed_in?
        current_client.form_submission_batches
      else
        FormSubmissionBatch.none
      end

    @monthly_batches = scope.where(created_at: current_month_range)

    @total_sent = @monthly_batches.sum(:total_count)
    @total_success = @monthly_batches.sum(:success_count)
    @total_failure = @monthly_batches.sum(:failure_count)

    @success_rate =
      @total_sent.positive? ? ((@total_success.to_f / @total_sent) * 100).round(1) : 0

    if admin_signed_in? && params[:client_id].present?
      client = Client.find(params[:client_id])
      monthly_log = client.monthly_usage_log
      @serp_api_limit = monthly_log.serp_api_limit
      @serp_api_used = monthly_log.serp_api_used
      @form_detection_limit = monthly_log.form_detection_limit
      @form_detection_used = monthly_log.form_detection_used
    elsif client_signed_in?
      monthly_log = current_client.monthly_usage_log
      @serp_api_limit = monthly_log.serp_api_limit
      @serp_api_used = monthly_log.serp_api_used
      @form_detection_limit = monthly_log.form_detection_limit
      @form_detection_used = monthly_log.form_detection_used
    else
      @serp_api_limit = 0
      @serp_api_used = 0
      @form_detection_limit = 0
      @form_detection_used = 0
    end

    click_scope =
      if admin_signed_in? && params[:client_id].present?
        ClickTrackingLink.where(client_id: params[:client_id])
      elsif admin_signed_in?
        ClickTrackingLink.all
      elsif client_signed_in?
        ClickTrackingLink.where(client_id: current_client.id)
      else
        ClickTrackingLink.none
      end

    click_scope = click_scope.where(created_at: current_month_range)

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

      if statuses.any? || from_date.present? || to_date.present?
        filtered_ids = filtered.includes(:last_form_call).select do |customer|
          call = customer.last_form_call
          next false if call.blank?

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

    detail_scope = FunnelEvent.where(created_at: since..)
                              .includes(click_tracking_link: [:customer, :submission])
                              .recent

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