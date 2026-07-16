require "securerandom"

class CustomersController < ApplicationController
  include RequiresExecutionAccess

  before_action :set_customers, only: [:update_all_status]
  before_action :authenticate_admin_or_client!, only: [:draft, :serp_search]
  require_execution_access! only: [:serp_search]
  protect_from_forgery with: :exception, prepend: true

  SERP_PREF_PATTERN = /東京都|大阪府|北海道|神奈川県|愛知県|福岡県|埼玉県|千葉県|兵庫県|静岡県|茨城県|広島県|京都府|宮城県|新潟県|長野県|岐阜県|群馬県|栃木県|岡山県|福島県|三重県|熊本県|鹿児島県|沖縄県|滋賀県|山口県|愛媛県|長崎県|奈良県|青森県|岩手県|大分県|石川県|山形県|宮崎県|富山県|秋田県|香川県|和歌山県|佐賀県|福井県|徳島県|高知県|島根県|鳥取県|山梨県/.freeze
  ADDRESS_MUNICIPALITY_PATTERN = /市|区|町|村|郡/.freeze
  ADDRESS_DETAIL_PATTERN = /[0-9０-９]|丁目|番地|番|号|[-－ー]/.freeze
  ADDRESS_ACCESS_PATTERN = /駅(?:\s|$|車|徒歩|バス|から|より|[0-9０-９]+分)|徒歩|車\s*[0-9０-９]+分|バス\s*[0-9０-９]+分|バス停|バス利用|バスで|バス約|分圏内|アクセス|最寄り/.freeze
  DISPLAY_TIME_ZONE = "Tokyo".freeze

  def index
    @last_call_params = params[:last_call] || {}

    @q = Customer.ransack(params[:q])
    @customers = @q.result.includes(:last_call)
    @customers = @customers.where("fobbiden IS NULL OR fobbiden != 'true'")
    @customers = @customers.where.not(tel: [nil, "", " "])
    @customers = @customers.left_joins(:last_call)
                           .where("calls.id IS NULL OR calls.status IS NULL")

    if @last_call_params.present?
      unless @last_call_params[:status].blank?
        @customers = @customers.joins(:last_call)
                               .where(calls: { status: @last_call_params[:status] })
      end
      unless @last_call_params[:time_from].blank?
        @customers = @customers.joins(:last_call)
                               .where("calls.time >= ?", @last_call_params[:time_from])
      end
      unless @last_call_params[:time_to].blank?
        @customers = @customers.joins(:last_call)
                               .where("calls.time <= ?", @last_call_params[:time_to])
      end
      unless @last_call_params[:created_at_from].blank?
        @customers = @customers.joins(:last_call)
                               .where("calls.created_at >= ?", @last_call_params[:created_at_from])
      end
      unless @last_call_params[:created_at_to].blank?
        @customers = @customers.joins(:last_call)
                               .where("calls.created_at <= ?", @last_call_params[:created_at_to])
      end
    end

    if params[:search] && params[:search][:ltec_calls_count].present?
      @customers = @customers.ltec_calls_count(params[:search][:ltec_calls_count].to_i)
    end

    @csv_customers = @customers.distinct
    @customers = @customers.distinct.page(params[:page]).per(100)

    respond_to do |format|
      format.html
      format.csv do
        send_data @csv_customers.generate_csv,
                  filename: "customers-#{Time.zone.now.strftime('%Y%m%d%S')}.csv"
      end
    end
  end

  def show
    @customer = Customer.find(params[:id])
    if client_signed_in? && @customer.client_id != current_client.id
      redirect_to customers_path, alert: 'アクセス権限がありません。'
      return
    end
    @submission_id = params[:submission_id]
    @all_ids = params[:all_ids].to_s.split(',').map(&:to_i)
    @current_index = params[:current_index].present? ? params[:current_index].to_i : (@all_ids.index(@customer.id) || 0)

    prev_id = (@current_index > 0) ? @all_ids[@current_index - 1] : nil
    next_id = (@current_index < @all_ids.length - 1) ? @all_ids[@current_index + 1] : nil

    @prev_customer = Customer.find_by(id: prev_id) if prev_id
    @next_customer = Customer.find_by(id: next_id) if next_id
  end

  def new
    @customer = Customer.new
  end

  def create
    @customer = Customer.new(customer_params)
    if @customer.save
      redirect_to customers_path, notice: "顧客を作成しました（バリデーションなし）"
    else
      flash.now[:alert] = @customer.errors.full_messages.join(", ")
      render :new
    end
  end

  def edit
    @customer = Customer.find(params[:id])
    if client_signed_in? && @customer.client_id != current_client.id
      redirect_to customers_path, alert: 'アクセス権限がありません。'
    end
  end

  def update
    @customer = Customer.find(params[:id])
    if client_signed_in? && @customer.client_id != current_client.id
      redirect_to customers_path, alert: 'アクセス権限がありません。'
      return
    end

    if params[:commit] == '対象外リストとして登録'
      @customer.skip_validation = true if @customer.respond_to?(:skip_validation=)
      @customer.status = "hidden"
    elsif params[:commit] == '公開して一覧へ'
      @customer.status = nil
    end

    if params[:commit] == '対象外リストとして登録'
      @customer.assign_attributes(customer_params)
      saved = @customer.save(validate: false)
    else
      saved = @customer.update(customer_params)
      sync_client_delivery_opt_out!(@customer) if saved && client_signed_in?
    end

    if saved
      if params[:commit] == '公開して一覧へ'
        redirect_to customers_path(
          q: params[:q]&.permit!,
          industry_name: params[:industry_name],
          tel_filter: params[:tel_filter]
        ) and return
      end

      query = Customer.where(status: 'draft').where('id > ?', @customer.id)
      query = query.where(business: params[:industry_name]) if params[:industry_name].present?

      case params[:tel_filter]
      when "with_tel"
        query = query.where.not("TRIM(tel) = ''")
      when "without_tel"
        query = query.where("TRIM(tel) = ''")
      end

      @next_draft = query.order(:id).first

      if @next_draft
        redirect_to edit_customer_path(@next_draft, q: params[:q]&.permit!, industry_name: params[:industry_name], tel_filter: params[:tel_filter]), notice: '更新しました。次の顧客を表示します。'
      else
        redirect_to customers_path(q: params[:q]&.permit!), notice: '更新しました。次の draft 顧客はありません。'
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def manual_call
    @customer = Customer.find(params[:id])
    Call.create!(customer_id: @customer.id, status: params[:status], comment: "手動送信")

    all_ids = params[:all_ids].to_s.split(',').map(&:to_i)
    current_idx = params[:current_index].to_i
    submission_id = params[:submission_id]

    if current_idx < all_ids.length - 1
      next_customer_id = all_ids[current_idx + 1]
      redirect_to customer_path(next_customer_id,
                  all_ids: params[:all_ids],
                  submission_id: submission_id,
                  current_index: current_idx + 1)
    else
      redirect_to history_submission_path(submission_id),
                  alert: '手動送信リストがなくなりました。管理者に連絡してください'
    end
  end

  def destroy
    @customer = Customer.find(params[:id])
    if client_signed_in? && @customer.client_id != current_client.id
      redirect_to customers_path, alert: 'アクセス権限がありません。'
      return
    end
    @customer.destroy
    redirect_to customers_path
  end

  def destroy_all
    checked_data = params[:deletes].keys
    if client_signed_in?
      checked_customers = Customer.where(id: checked_data, client_id: current_client.id)
    else
      checked_customers = Customer.where(id: checked_data)
    end
    deleted_count = checked_customers.destroy_all
    if deleted_count.present?
      redirect_to customers_path, notice: "draftから#{deleted_count.size}件削除しました。"
    else
      redirect_to customers_path, alert: '削除に失敗しました。'
    end
  end

  def all_import
    uploaded_file = params[:file]
    csv_content = uploaded_file.read

    overwrite_blank = admin_signed_in? && params[:overwrite_blank] == '1'
    client_id = current_client.id if respond_to?(:current_client) && current_client

    CustomerImportJob.perform_later(
      csv_content,
      overwrite_blank,
      client_id
    )
    redirect_to customers_url, notice: 'インポート処理をバックグラウンドで実行しています。完了後、通知で結果をお知らせします。'
  end

def draft
  start_time = Time.current

  parse_period_params

  draft_scope_args = {
    current_client_id: client_signed_in? ? current_client.id : nil,
    is_admin:          admin_signed_in?
  }

  @industry_base_scope = Customer.draft_base_scope(**draft_scope_args, industry_name: nil)
  base_scope = Customer.draft_base_scope(**draft_scope_args, industry_name: params[:industry_name].presence)

  @company_query = params[:company_query].presence

  serp_target_base = base_scope.serp_extraction_targets(params[:fill_filter])
  serp_target_base = filter_company_query(serp_target_base, @company_query) if @company_query.present?

  main_scope = base_scope
  main_scope = filter_company_query(main_scope, @company_query) if @company_query.present?

  @customers = main_scope
                 .apply_status_filter(params[:status_filter])
                 .apply_serp_status_filter(params[:serp_status_filter])
                 .apply_tel_role_filter(
                   is_admin:   admin_signed_in?,
                   is_worker:  worker_signed_in?,
                   tel_filter: params[:tel_filter]
                 )
                 .apply_fill_filter(params[:fill_filter])
                 .apply_updated_at_filter(
                   params[:updated_from],
                   params[:updated_to],
                   params[:updated_today]
                 )
                 .apply_created_at_range(@range_start, @range_end)
                 .order(updated_at: :desc)
                 .page(params[:page])
                 .per(100)

  @filtered_count = @customers.total_count

  @serp_targets = serp_target_base.order(id: :asc)
                                  .page(params[:serp_page])
                                  .per(20)
  @serp_target_count = @serp_targets.total_count

  raw_remaining = ExtractTracking.remaining_extractable_count

  if client_signed_in? && !admin_signed_in?
    monthly_log = current_client.monthly_usage_log
    subscription_remaining = [monthly_log.serp_api_limit - monthly_log.serp_api_used, 0].max
    @remaining_extractable = [subscription_remaining, @serp_target_count].min
  else
    @remaining_extractable = [raw_remaining, @serp_target_count].min
  end

  @dashboard_stats = Customer.calculate_dashboard_stats(base_scope)

  selected_industry = params[:industry_name].presence
  industry_scope = @industry_base_scope.with_legal_entity
                                       .where.not(business: [nil, ''])
                                       .group(:business)

  industry_counts =
    if selected_industry.present?
      industry_scope.having("COUNT(*) >= 10 OR business = ?", selected_industry).count
    else
      industry_scope.having("COUNT(*) >= 10").count
    end

  @industry_options = industry_counts
                        .sort_by { |_name, count| -count }
                        .map { |name, count| ["#{name}（#{count}件）", name] }

  @max_search_limit = admin_signed_in? ? @serp_target_count
                                       : [@serp_target_count, @remaining_extractable].min

  elapsed = ((Time.current - start_time) * 1000).round(2)
  Rails.logger.info("draft action: completed in #{elapsed}ms")
end

def serp_search
  self.class.skip_before_action :verify_authenticity_token, only: [:serp_search], raise: false

  industry        = params[:industry].presence
  limit           = (params[:limit] || 100).to_i
  company_query   = params[:company_query].presence
  fill_filter     = params[:fill_filter].presence

  if client_signed_in? && !admin_signed_in?
    monthly_log = current_client.monthly_usage_log
    subscription_remaining = [monthly_log.serp_api_limit - monthly_log.serp_api_used, 0].max

    if subscription_remaining <= 0
      redirect_to dashboard_index_path, alert: "今月のSERP API使用上限に達しています（#{monthly_log.serp_api_used}/#{monthly_log.serp_api_limit}）" and return
    end

    limit = [limit, subscription_remaining].min
  end

  base_scope = Customer.draft_base_scope(
    current_client_id: client_signed_in? ? current_client.id : nil,
    is_admin:          admin_signed_in?,
    industry_name:     industry
  )

  scope = base_scope.serp_extraction_targets(fill_filter)

  if company_query.present?
    scope = filter_company_query(scope, company_query)
  end

  target_count = scope.count

  if target_count == 0
    redirect_to dashboard_index_path, alert: "SERP補完の対象データが存在しません。" and return
  end

  actual_limit = [limit, target_count].min
  customer_ids = scope.order(id: :asc).limit(actual_limit).pluck(:id)

  if ENV["BRIGHT_DATA_API_KEY"].to_s.strip.blank?
    redirect_to dashboard_index_path,
      alert: "BRIGHT_DATA_API_KEY が未設定です。.env を確認し、Rails/Sidekiqを再起動してから再実行してください。" and return
  end

  sidekiq = SerpSidekiqManager.ensure_running
  unless sidekiq.ready?
    redirect_to dashboard_index_path, alert: sidekiq.message and return
  end

  client_id = client_signed_in? ? current_client.id : nil

  run_id = SecureRandom.uuid
  audit_run = SerpEnrichmentRun.create_for_targets!(
    run_id: run_id,
    industry: industry,
    limit: actual_limit,
    targets: Customer.where(id: customer_ids)
  )
  audit_run.update!(client_id: client_id)

  begin
    serp_queue = PlanPriorityQueue.queue_for(
      :serp_enrichment,
      client: current_client,
      admin: admin_signed_in?
    )
    SerpPipelineDbWorker.set(queue: serp_queue).perform_async(industry, customer_ids, run_id, 0, serp_queue.to_s)
    batch_size = SerpPipelineDbWorker::BATCH_SIZE
    wait_notice = PlanPriorityQueue.wait_notice_for(client: current_client, admin: admin_signed_in?)
    prefix = if sidekiq.started? && sidekiq.redis_started?
      "RedisとSERP専用Sidekiqを起動してから"
    elsif sidekiq.started?
      "SERP専用Sidekiqを起動してから"
    else
      ""
    end
    notice_message = "#{prefix}SERP補完をバックグラウンドで開始しました。対象: #{actual_limit}件（#{batch_size}件ずつ処理・失敗時は中断 / 業種: #{industry || '全業種'}）"
    notice_message = "#{notice_message} #{wait_notice}" if wait_notice.present?
    redirect_to dashboard_index_path, notice: notice_message
  rescue Redis::CannotConnectError, Errno::ECONNREFUSED => e
    Rails.logger.warn("[serp_search] Redis接続不可: #{e.message}")
    redirect_to dashboard_index_path,
      alert: "Redisに接続できないため、SERP補完を開始できませんでした。Redisを起動してから再実行してください。"
  end
end

  private

  def authenticate_admin_or_client!
    unless admin_signed_in? || client_signed_in?
      respond_to do |format|
        format.html { redirect_to new_client_session_path, alert: 'ログインが必要です。' }
        format.json { render json: { error: 'Unauthorized' }, status: :unauthorized }
      end
    end
  end

  def set_customers
    customer_ids = params[:deletes]&.keys
    if customer_ids.present?
      @customers = Customer.where(id: customer_ids)
    else
      @customers = Customer.none
    end
  end

  def parse_period_params
    @period_start = Date.parse(params[:period_start]) rescue nil if params[:period_start].present?
    @period_end   = Date.parse(params[:period_end])   rescue nil if params[:period_end].present?

    if @period_start.present? && @period_end.present? && @period_end < @period_start
      @period_start, @period_end = @period_end, @period_start
    end

    @range_start = @period_start&.beginning_of_day
    @range_end   = @period_end&.end_of_day
  end

  def serp_worker_running?
    SerpSidekiqManager.worker_running?
  end

  def serp_queue_size
    SerpSidekiqManager.queue_size
  end

  def redis_reachable?
    SerpSidekiqManager.redis_reachable?
  end

  def redis_auto_start_possible?
    SerpSidekiqManager.redis_auto_start_possible?
  end

  def current_serp_progress_payload
    SerpProgressTracker.payload(session[:serp_progress_run_id])
  end

  def filter_company_query(scope, query)
    terms = query.to_s.strip.split(/[[:space:] ']+/).reject(&:blank?)
    terms.reduce(scope) do |relation, term|
      escaped = ActiveRecord::Base.sanitize_sql_like(term)
      relation.where("company LIKE ?", "%#{escaped}%")
    end
  end

  def filter_detailed_address(scope)
    ids = scope.pluck(:id, :address).select { |_, address| detailed_address_value?(address) }.map(&:first)
    scope.where(id: ids)
  end

  def filter_partial_address(scope)
    ids = scope.pluck(:id, :address).reject { |_, address| detailed_address_value?(address) }.map(&:first)
    scope.where(id: ids)
  end

  def filter_official_url(scope)
    ids = scope.pluck(:id, :url).select { |_, url| official_url_value?(url) }.map(&:first)
    scope.where(id: ids)
  end

  def filter_missing_official_url(scope)
    ids = scope.pluck(:id, :url).reject { |_, url| official_url_value?(url) }.map(&:first)
    scope.where(id: ids)
  end

  def detailed_address_count(scope)
    scope.pluck(:address).count { |address| detailed_address_value?(address) }
  end

  def official_url_count(scope)
    scope.pluck(:url).count { |url| official_url_value?(url) }
  end

  def detailed_address_value?(address)
    normalized = address.to_s.strip
    return false if normalized.blank?
    return false if normalized.match?(ADDRESS_ACCESS_PATTERN)
    return false if BrightData::Pipeline.send(:address_score, normalized).zero?

    normalized.match?(SERP_PREF_PATTERN) &&
      normalized.match?(ADDRESS_MUNICIPALITY_PATTERN) &&
      normalized.match?(ADDRESS_DETAIL_PATTERN)
  end

  def official_url_value?(url)
    BrightData::UrlPolicy.official_url?(url)
  end

  def zoned_today_range
    today = Time.current.in_time_zone(DISPLAY_TIME_ZONE).to_date
    zoned_beginning_of_day(today)..zoned_end_of_day(today)
  end

  def zoned_beginning_of_day(date)
    Time.find_zone!(DISPLAY_TIME_ZONE).local(date.year, date.month, date.day).beginning_of_day
  end

  def zoned_end_of_day(date)
    Time.find_zone!(DISPLAY_TIME_ZONE).local(date.year, date.month, date.day).end_of_day
  end

  def display_customer_names
    customer_info = []
    INDUSTRY_MAPPING.each do |customer_name, info|
      customer_info << "#{customer_name}: #{info[:company_name]}"
    end
    customer_info
  end

  def calculate_app_calls_counts
    counts = {}
    @industry_mapping.each do |key, value|
      calls = Customer.joins(:calls).where(industry: value[:industry], calls: { status: 'APP' }).count
      counts[key] = calls
    end
    counts
  end

  public

  def bulk_action
    if client_signed_in?
      @customers = Customer.where(id: params[:deletes].keys, client_id: current_client.id)
    else
      @customers = Customer.where(id: params[:deletes].keys)
    end

    if params[:commit] == '一括更新'
      update_all_status
    elsif params[:commit] == '一括削除'
      destroy_all
    elsif params[:commit] == '一括削除（社名）'
      destroy_all_by_company
    else
      redirect_to customers_path, alert: '無効なアクションです。'
    end
  end

  def update_all_status
    status = params[:status] || 'hidden'
    published_count = 0
    hidden_count    = 0
    deleted_count   = 0
    reposted_count  = 0

    @customers.each do |customer|
      customer.skip_validation = true

      if customer.status == 'draft'
        normalized_company = Customer.normalized_name(customer.company)
        normalized_tel     = customer.tel.to_s.delete('-')

        existing_customer = Customer.where(business: customer.business, status: nil)
                                    .where.not(id: customer.id)
                                    .find do |c|
          c_tel      = c.tel.to_s.delete('-')
          tel_match  = normalized_tel.present? && c_tel.present? && normalized_tel == c_tel
          c_company  = Customer.normalized_name(c.company)
          name_match = Customer.name_similarity?(normalized_company, c_company)
          tel_match || name_match
        end

        if existing_customer
          latest_call = existing_customer.calls.order(created_at: :desc).first

          if latest_call && latest_call.created_at <= 2.months.ago
            unless %w(APP 永久NG 見込).include?(latest_call.status)
              existing_customer.calls.create(status: '再掲載')
              customer.worker.increment!(:deleted_customer_count) if customer.worker.present?
              customer.destroy
              reposted_count += 1
              next
            end
          end

          customer.worker.increment!(:deleted_customer_count) if customer.worker.present?
          customer.destroy
          deleted_count += 1
          next
        end
      end

      if status == 'hidden'
        hidden_count += 1 if customer.update_columns(status: 'hidden')
      else
        published_count += 1 if customer.update_columns(status: nil)
      end
    end

    flash[:notice] = "#{published_count}件が公開され、#{hidden_count}件が非表示にされ、#{reposted_count}件を再掲載に登録しました。#{deleted_count}件のドラフトが重複のため削除されました。"
    redirect_to customers_path
  end

  def cleanup_duplicates
    attribute = params[:attribute]
    redirect_path = dashboard_duplication_path

    unless Customer::DUPLICATE_CLEANUP_ATTRIBUTES.include?(attribute)
      return redirect_to(redirect_path, alert: "不正な属性指定です。")
    end

    CustomerDuplicateCleanupJob.perform_later(
      attribute,
      client_signed_in?,
      admin_signed_in?,
      current_client&.id
    )

    redirect_to redirect_path,
                notice: "重複削除をバックグラウンドで開始しました。完了後に通知します。"
  rescue StandardError => e
    Rails.logger.error("[cleanup_duplicates] #{e.class}: #{e.message}\n#{e.backtrace&.first(10)&.join("\n")}")
    redirect_to redirect_path, alert: "重複削除の開始に失敗しました: #{e.message}"
  end

  def extract_company_info
    start_time    = Time.current
    industry_name = params[:industry_name]
    total_count   = params[:count]

    tracking = ExtractTracking.create!(
      industry:      industry_name,
      total_count:   total_count,
      success_count: 0,
      failure_count: 0,
      status:        "抽出中"
    )

    begin
      ExtractCompanyInfoWorker.new.perform(tracking.id)
      tracking.reload

      if tracking.status == "抽出完了"
        flash[:notice] = "抽出処理が正常に完了しました。（#{tracking.success_count}件成功 / #{tracking.failure_count}件失敗）"
      else
        flash[:alert] = "抽出処理が中断または失敗しました。（ステータス: #{tracking.status}）"
      end
    rescue => e
      Rails.logger.error("Sync execution failed: #{e.message}")
      flash[:alert] = "システムエラーにより抽出処理が失敗しました。"
    end

    elapsed = ((Time.current - start_time) * 1000).round(2)
    Rails.logger.info("extract_company_info: completed in #{elapsed}ms (tracking_id: #{tracking.id})")
    redirect_to draft_path
  end

  def extract_progress
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma']        = 'no-cache'
    response.headers['Expires']       = '0'

    industry = params[:industry].to_s.presence

    if industry
      tracking = ExtractTracking.where(industry: industry).order(id: :desc).first
      if tracking
        render json: tracking.progress_payload
      else
        render json: { message: 'no_tracking' }
      end
    else
      crowdworks     = Crowdwork.all || []
      industry_names = crowdworks.map(&:title)
      all_trackings  = ExtractTracking.where(industry: industry_names).order(id: :desc)
      latest_trackings = all_trackings.group_by(&:industry).transform_values { |trackings| trackings.first }

      progress_data = {}
      crowdworks.each do |crowdwork|
        tracking = latest_trackings[crowdwork.title]
        progress_data[crowdwork.title] = tracking ? tracking.progress_payload : { message: 'no_tracking' }
      end
      render json: progress_data
    end
  end

  def serp_progress
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma']        = 'no-cache'
    response.headers['Expires']       = '0'

    render json: current_serp_progress_payload
  end

  private

  def sync_client_delivery_opt_out!(customer)
    return unless current_client.present?

    if params[:client_delivery_opt_out] == '1'
      DeliveryOptOut.find_or_create_by!(customer: customer, client: current_client)
    else
      DeliveryOptOut.where(customer: customer, client_id: current_client.id).delete_all
    end
  end

  def customer_params
    params.require(:customer).permit(
      :company,
      :name,
      :tel,
      :address,
      :mobile,
      :industry,
      :email,
      :url,
      :business,
      :genre,
      :contact_form,
      :contact_url,
      :fobbiden,
      :remarks,
    )
  end
end