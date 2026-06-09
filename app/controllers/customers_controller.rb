require "securerandom"

class CustomersController < ApplicationController
  before_action :set_customers, only: [:update_all_status]
  before_action :authenticate_admin_or_client!, only: [:draft]
  protect_from_forgery with: :exception, prepend: true

  # SERP補完対象判定用正規表現（SQLite REGEXP非対応のためRubyで判定）
  SERP_CORP_PATTERN = /株式会社|有限会社|合同会社|一般社団法人|一般財団法人|社会福祉法人|医療法人|学校法人/.freeze
  SERP_PREF_PATTERN = /東京都|大阪府|北海道|神奈川県|愛知県|福岡県|埼玉県|千葉県|兵庫県|静岡県|茨城県|広島県|京都府|宮城県|新潟県|長野県|岐阜県|群馬県|栃木県|岡山県|福島県|三重県|熊本県|鹿児島県|沖縄県|滋賀県|山口県|愛媛県|長崎県|奈良県|青森県|岩手県|大分県|石川県|山形県|宮崎県|富山県|秋田県|香川県|和歌山県|佐賀県|福井県|徳島県|高知県|島根県|鳥取県|山梨県/.freeze
  ADDRESS_MUNICIPALITY_PATTERN = /市|区|町|村|郡/.freeze
  ADDRESS_DETAIL_PATTERN = /[0-9０-９]|丁目|番地|番|号|[-－ー]/.freeze
  ADDRESS_ACCESS_PATTERN = /駅(?:\s|$|車|徒歩|バス|から|より|[0-9０-９]+分)|徒歩|車\s*[0-9０-９]+分|バス\s*[0-9０-９]+分|バス停|バス利用|バスで|バス約|分圏内|アクセス|最寄り/.freeze
  DISPLAY_TIME_ZONE = "Tokyo".freeze

def index
  @last_call_params = params[:last_call] || {}

  # Ransack で検索
  @q = Customer.ransack(params[:q])
  @customers = @q.result.includes(:last_call)

  # fobbiden=true を除外
  @customers = @customers.where("fobbiden IS NULL OR fobbiden != 'true'")

  # 電話番号がある顧客に絞る
  @customers = @customers.where.not(tel: [nil, "", " "])

  # 最後のコールが nil か status が nil の顧客を SQL 側でフィルタ
  @customers = @customers.left_joins(:last_call)
                         .where("calls.id IS NULL OR calls.status IS NULL")

  # last_call_params があればフィルタ
  if @last_call_params.present?
    # status 条件
    unless @last_call_params[:status].blank?
      @customers = @customers.joins(:last_call)
                             .where(calls: { status: @last_call_params[:status] })
    end

    # time 条件
    unless @last_call_params[:time_from].blank?
      @customers = @customers.joins(:last_call)
                             .where("calls.time >= ?", @last_call_params[:time_from])
    end

    unless @last_call_params[:time_to].blank?
      @customers = @customers.joins(:last_call)
                             .where("calls.time <= ?", @last_call_params[:time_to])
    end

    # created_at 条件
    unless @last_call_params[:created_at_from].blank?
      @customers = @customers.joins(:last_call)
                             .where("calls.created_at >= ?", @last_call_params[:created_at_from])
    end

    unless @last_call_params[:created_at_to].blank?
      @customers = @customers.joins(:last_call)
                             .where("calls.created_at <= ?", @last_call_params[:created_at_to])
    end
  end

  # ltec_calls_count フィルタ
  if params[:search] && params[:search][:ltec_calls_count].present?
    @customers = @customers.ltec_calls_count(params[:search][:ltec_calls_count].to_i)
  end

  # CSV 用データ
  @csv_customers = @customers.distinct

  # ページネーション
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
  @submission_id = params[:submission_id]
  @all_ids = params[:all_ids].to_s.split(',').map(&:to_i)
  
  # URLで指定されたインデックスを優先（見つからない場合のみ検索）
  @current_index = params[:current_index].present? ? params[:current_index].to_i : (@all_ids.index(@customer.id) || 0)

  # 前後の判定（ループさせない）
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
end

def update
  @customer = Customer.find(params[:id])

  # 1. 共通の属性変更（コミットボタンに応じたステータス調整）
  if params[:commit] == '対象外リストとして登録'
    @customer.skip_validation = true if @customer.respond_to?(:skip_validation=)
    @customer.status = "hidden"
  elsif params[:commit] == '公開して一覧へ'
    @customer.status = nil
  end

  # 2. パラメータの反映と保存（保存処理を1回に集約）
  # コミットボタンの種類に関わらず、フォームの入力値(customer_params)も同時に更新する場合の構成
  if params[:commit] == '対象外リストとして登録'
    @customer.assign_attributes(customer_params)
    saved = @customer.save(validate: false)
  else
    saved = @customer.update(customer_params)
  end

  # 3. 保存成否とコミットボタンに応じた画面遷移・後続処理
  if saved
    if params[:commit] == '公開して一覧へ'
      redirect_to customers_path(
        q: params[:q]&.permit!,
        industry_name: params[:industry_name],
        tel_filter: params[:tel_filter]
      ) and return
    end

    # 次の draft 顧客を取得（フィルタ考慮）
    query = Customer.where(status: 'draft').where('id > ?', @customer.id)
    query = query.where(industry: params[:industry_name]) if params[:industry_name].present?

    case params[:tel_filter]
    when "with_tel"
      query = query.where.not("TRIM(tel) = ''")
    when "without_tel"
      query = query.where("TRIM(tel) = ''")
    end

    @next_draft = query.order(:id).first

    # 次の顧客がいればその詳細(編集)画面へ、いなければ一覧へ戻る等の制御（※環境に合わせて調整してください）
    if @next_draft
      redirect_to edit_customer_path(@next_draft, q: params[:q]&.permit!, industry_name: params[:industry_name], tel_filter: params[:tel_filter]), notice: '更新しました。次の顧客を表示します。'
    else
      redirect_to customers_path(q: params[:q]&.permit!), notice: '更新しました。次の draft 顧客はありません。'
    end
  else
    # バリデーションエラー等の場合
    render :edit, status: :unprocessable_entity
  end
end

def manual_call
  @customer = Customer.find(params[:id])
  Call.create!(customer_id: @customer.id, status: params[:status], comment: "手動送信")

  all_ids = params[:all_ids].to_s.split(',').map(&:to_i)
  current_idx = params[:current_index].to_i
  submission_id = params[:submission_id]

  # 【重要】現在のインデックスがリストの最後（length - 1）かどうかで判定
  if current_idx < all_ids.length - 1
    next_customer_id = all_ids[current_idx + 1]
    redirect_to customer_path(next_customer_id, 
                all_ids: params[:all_ids], 
                submission_id: submission_id,
                current_index: current_idx + 1)
  else
    # 最後のIDだった場合は history へ。メッセージを出す。
    redirect_to history_submission_path(submission_id), 
                alert: '手動送信リストがなくなりました。管理者に連絡してください'
  end
end

def destroy
    @customer = Customer.find(params[:id])
    @customer.destroy
    redirect_to customers_path
  end

  def destroy_all
    checked_data = params[:deletes].keys # チェックされたデータを取得
    deleted_count = Customer.where(id: checked_data).destroy_all # 削除処理を実行
    if deleted_count.present?
      redirect_to customers_path, notice: "draftから#{deleted_count.size}件削除しました。" # 削除件数を含めたメッセージ
    else
      redirect_to customers_path, alert: '削除に失敗しました。'
    end
  end

  def all_import
    uploaded_file = params[:file]
  
    temp_file_path = Rails.root.join('tmp', "#{SecureRandom.uuid}_#{uploaded_file.original_filename}")
    File.open(temp_file_path, 'wb') do |file|
      file.write(uploaded_file.read)
    end
  
    CustomerImportJob.perform_later(temp_file_path.to_s)
  
    redirect_to customers_url, notice: 'インポート処理をバックグラウンドで実行しています。完了までしばらくお待ちください。'
  end

  def draft
    start_time = Time.current

    # 1. 期間パラメータのパース
    parse_period_params

    # 2. 権限や業種に応じたベーススコープをモデルから取得
    base_scope = Customer.draft_base_scope(
      current_client_id: client_signed_in? ? current_client.id : nil,
      is_admin: admin_signed_in?,
      industry_name: params[:industry_name]
    )

    # 社名検索パラメータの取得
    @company_query = params[:company_query].presence

    # 未抽出・補完対象（@serp_targets）用のベーススコープを構築
    # (serp_status が未処理、かつ tel/url/contact_url のいずれかが空のデータ)
    serp_target_base = base_scope.where(serp_status: [nil, ''])
                                 .where(
                                   "(tel IS NULL OR TRIM(tel) = '') OR " \
                                   "(url IS NULL OR TRIM(url) = '') OR " \
                                   "(contact_url IS NULL OR TRIM(contact_url) = '')"
                                 )

    # 未抽出エリアへの検索機能の適用（社名検索が指定されていれば絞り込む）
    if @company_query.present?
      serp_target_base = filter_company_query(serp_target_base, @company_query)
    end

    # 3. 画面表示用のメイン顧客リストの絞り込み
    # メインリスト側も社名検索が指定されていれば絞り込む
    main_scope = base_scope
    if @company_query.present?
      main_scope = filter_company_query(main_scope, @company_query)
    end

    @customers = main_scope
                   .apply_status_filter(params[:status_filter])
                   .apply_serp_status_filter(params[:serp_status_filter])
                   .apply_tel_role_filter(is_admin: admin_signed_in?, is_worker: worker_signed_in?, tel_filter: params[:tel_filter])
                   .apply_fill_filter(params[:fill_filter])
                   .apply_updated_at_filter(params[:updated_from], params[:updated_to], params[:updated_today])
                   .apply_created_at_range(@range_start, @range_end)

    # メインリストの順序制御・ページネーション・件数取得 (100件区切り)
    @customers = @customers.order(updated_at: :desc).includes(:worker).page(params[:page]).per(100)
    @filtered_count = @customers.total_count

    # 4. 「実行前に対象となる企業」のデータを20件でページネーション
    @serp_targets = serp_target_base.order(id: :asc)
                                    .page(params[:serp_page])
                                    .per(20)

    # 5. 残り抽出可能件数の取得（モデルから算出）
    # クライアントの場合は、契約やシステムの上限に加えて、自身の検索スコープに合致する「補完対象の総件数」を絶対に超えないよう上限を丸める
    raw_remaining = ExtractTracking.remaining_extractable_count
    @serp_target_count = serp_target_base.count # 検索・フィルタ反映後の補完対象件数

    if client_signed_in? && !admin_signed_in?
      @remaining_extractable = [raw_remaining, @serp_target_count].min
    else
      @remaining_extractable = raw_remaining
    end

    # 6. 統計情報の取得（ダッシュボード等で利用するベース統計）
    @dashboard_stats = Customer.calculate_dashboard_stats(base_scope)

    # ビュー側で「SERP API START」に渡す上限設定パラメータ（クライアント時は残り抽出可能件数でクリップ）
    @max_search_limit = admin_signed_in? ? @serp_target_count : [@serp_target_count, @remaining_extractable].min

    elapsed = ((Time.current - start_time) * 1000).round(2)
    Rails.logger.info("draft action: completed in #{elapsed}ms")
  end
  # POST /customers/serp_search
def serp_search
    # ブラウザからCookieが送られずセッションが空（nil）であっても、
    # このアクションだけはCSRF検問をスルーして確実にSidekiqへ処理を流すようにします。
    self.class.skip_before_action :verify_authenticity_token, only: [:serp_search], raise: false

    industry  = params[:industry].presence
    limit     = (params[:limit] || 100).to_i

    # 対象件数を事前確認（serp_status NULL かつ tel/url/contact_url いずれか空）
    scope = Customer.where(serp_status: [nil, ''])
                    .where(
                      "(tel IS NULL OR TRIM(tel) = '') OR " \
                      "(url IS NULL OR TRIM(url) = '') OR " \
                      "(contact_url IS NULL OR TRIM(contact_url) = '')"
                    )
    scope = scope.where(industry: industry) if industry.present?
    target_count = scope.count

    if target_count == 0
      redirect_to draft_customers_path, alert: "SERP補完の対象データが存在しません。" and return
    end

    # Sidekiq経由で非同期実行。Redisが未起動の場合は同期フォールバック
    actual_limit = [limit, target_count].min
    begin
      SerpPipelineDbWorker.perform_async(industry, actual_limit)
      redirect_to draft_customers_path,
        notice: "SERP補完をバックグラウンドで開始しました。対象: #{actual_limit}件（業種: #{industry || '全業種'}）"
    rescue Redis::CannotConnectError, Errno::ECONNREFUSED => e
      Rails.logger.warn("[serp_search] Redis未起動のため同期実行にフォールバック: #{e.message}")
      begin
        BrightData::Pipeline.execute_from_db(industry: industry.presence, limit: actual_limit, dry_run: false)
        redirect_to draft_customers_path,
          notice: "SERP補完が完了しました（同期実行）。対象: #{actual_limit}件（業種: #{industry || '全業種'}）"
      rescue => pipeline_err
        Rails.logger.error("[serp_search] Pipeline error: #{pipeline_err.message}")
        redirect_to draft_customers_path, alert: "SERP補完中にエラーが発生しました: #{pipeline_err.message}"
      end
    end
  end
  def filter_by_industry
    @crowdworks = Crowdwork.all || []

    @period_start = nil
    @period_end   = nil
    if params[:period_start].present?
      begin
        @period_start = Date.parse(params[:period_start])
      rescue ArgumentError
        @period_start = nil
      end
    end
    if params[:period_end].present?
      begin
        @period_end = Date.parse(params[:period_end])
      rescue ArgumentError
        @period_end = nil
      end
    end

    if @period_start.present? && @period_end.present? && @period_end < @period_start
      @period_start, @period_end = @period_end, @period_start
    end
    range_start = @period_start&.beginning_of_day
    range_end   = @period_end&.end_of_day

    industry_name = params[:industry_name]
    base_query = Customer.where(status: "draft")
    if range_start && range_end
      base_query = base_query.where(created_at: range_start..range_end)
    elsif range_start
      base_query = base_query.where('created_at >= ?', range_start)
    elsif range_end
      base_query = base_query.where('created_at <= ?', range_end)
    end
    base_query = base_query.where(industry: industry_name) if industry_name.present?

    @customers = case
    when admin_signed_in? && params[:tel_filter] == "with_tel"
      base_query.where.not(tel: [nil, '', ' '])
    when admin_signed_in? && params[:tel_filter] == "without_tel"
      base_query.where(tel: [nil, '', ' '])
    when worker_signed_in?
      base_query.where(tel: [nil, '', ' '])
    else
      base_query.where.not(tel: [nil, '', ' '])
    end

    tel_with_scope = Customer.where(status: "draft").where.not(tel: [nil, '', ' '])
    tel_without_scope = Customer.where(status: "draft").where(tel: [nil, '', ' '])
    if range_start && range_end
      tel_with_scope = tel_with_scope.where(created_at: range_start..range_end)
      tel_without_scope = tel_without_scope.where(created_at: range_start..range_end)
    elsif range_start
      tel_with_scope = tel_with_scope.where('created_at >= ?', range_start)
      tel_without_scope = tel_without_scope.where('created_at >= ?', range_start)
    elsif range_end
      tel_with_scope = tel_with_scope.where('created_at <= ?', range_end)
      tel_without_scope = tel_without_scope.where('created_at <= ?', range_end)
    end
    tel_with_counts = tel_with_scope.group(:industry).count
    tel_without_counts = tel_without_scope.group(:industry).count

    industry_names = @crowdworks.map(&:title)
    all_trackings = ExtractTracking.where(industry: industry_names).order(id: :desc)
    latest_trackings = all_trackings.group_by(&:industry).transform_values { |trackings| trackings.first }

    @industry_counts = @crowdworks.each_with_object({}) do |crowdwork, hash|
      latest_tracking = latest_trackings[crowdwork.title]
      success_count = latest_tracking&.success_count.to_i
      failure_count = latest_tracking&.failure_count.to_i
      total_count   = latest_tracking&.total_count.to_i
      total = success_count + failure_count
      rate = total.positive? ? (success_count.to_f / total) * 100 : 0.0
      hash[crowdwork.title] = {
        tel_with: tel_with_counts[crowdwork.title] || 0,
        tel_without: tel_without_counts[crowdwork.title] || 0,
        success_count: success_count,
        failure_count: failure_count,
        total_count: total_count,
        rate: rate,
        status: latest_tracking&.status || "抽出前"
      }
    end

    @customers = @customers.page(params[:page]).per(100)

    today_total = ExtractTracking
                    .where(created_at: Time.current.beginning_of_day..Time.current.end_of_day)
                    .sum(:total_count)
    daily_limit = ENV.fetch('EXTRACT_DAILY_LIMIT', '500').to_i
    @remaining_extractable = [daily_limit - today_total, 0].max

    base_scope = Customer.draft_base_scope(
      current_client_id: client_signed_in? ? current_client.id : nil,
      is_admin: admin_signed_in?,
      industry_name: params[:industry_name]
    )

    @serp_targets = base_scope.where(serp_status: [nil, ''])
                              .where(
                                "(tel IS NULL OR TRIM(tel) = '') OR " \
                                "(url IS NULL OR TRIM(url) = '') OR " \
                                "(contact_url IS NULL OR TRIM(contact_url) = '')"
                              )
                              .order(id: :asc)
                              .page(params[:serp_page])
                              .per(20)

    @serp_target_count = Customer.calculate_serp_target_count(base_scope)
    @dashboard_stats   = Customer.calculate_dashboard_stats(base_scope)

    render :draft
  end
  
  def extract_company_info
    start_time = Time.current
    Rails.logger.info("extract_company_info called (SYNC MODE).")
    industry_name = params[:industry_name]
    total_count = params[:count]

    tracking = ExtractTracking.create!(
      industry:       industry_name,
      total_count:    total_count,
      success_count:  0,
      failure_count:  0,
      status:         "抽出中"
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
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    
    industry = params[:industry].to_s.presence
    
    if industry
      tracking = ExtractTracking.where(industry: industry).order(id: :desc).first
      if tracking
        render json: tracking.progress_payload
      else
        render json: { message: 'no_tracking' }
      end
    else
      crowdworks = Crowdwork.all || []
      industry_names = crowdworks.map(&:title)
      all_trackings = ExtractTracking.where(industry: industry_names).order(id: :desc)
      latest_trackings = all_trackings.group_by(&:industry).transform_values { |trackings| trackings.first }
      
      progress_data = {}
      crowdworks.each do |crowdwork|
        tracking = latest_trackings[crowdwork.title]
        if tracking
          progress_data[crowdwork.title] = tracking.progress_payload
        else
          progress_data[crowdwork.title] = { message: 'no_tracking' }
        end
      end
      render json: progress_data
    end
  end
  
  def serp_progress
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'

    render json: current_serp_progress_payload
  end

  def bulk_action
    @customers = Customer.where(id: params[:deletes].keys)
  
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
    hidden_count = 0
    deleted_count = 0
    reposted_count = 0

    @customers.each do |customer|
      customer.skip_validation = true

      if customer.status == 'draft'
        normalized_company = Customer.normalized_name(customer.company)
        normalized_tel = customer.tel.to_s.delete('-')

        existing_customer = Customer.where(industry: customer.industry, status: nil)
                                    .where.not(id: customer.id)
                                    .find do |c|
          c_tel = c.tel.to_s.delete('-')
          tel_match = normalized_tel.present? && c_tel.present? && normalized_tel == c_tel
          c_company = Customer.normalized_name(c.company)
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
    valid_attributes = %w[company tel url contact_url]

    unless valid_attributes.include?(attribute)
      return redirect_to(request.referer || form_submissions_path, alert: "不正な属性指定です。")
    end

    duplicate_values = Customer
      .where.not(attribute => nil)
      .where.not("TRIM(#{attribute}) = ''")
      .group(attribute)
      .having("COUNT(id) > 1")
      .pluck(attribute)

    total_deleted = 0

    Customer.transaction do
      duplicate_values.each do |value|
        ids = Customer.where(attribute => value).order(id: :asc).pluck(:id)
        ids.shift
        deleted_records = Customer.where(id: ids).destroy_all
        total_deleted += deleted_records.size
      end
    end

    redirect_to request.referer || form_submissions_path,
                notice: "#{attribute}の重複分 #{total_deleted} 件を削除しました。"
  end

  private

  # ── プライベート領域（これより下はアクションとして外部公開されない） ──

  def authenticate_admin_or_client!
    unless admin_signed_in? || client_signed_in?
      render json: { error: 'Unauthorized' }, status: :unauthorized
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
      puts "Key: #{key}, Value: #{value}, Calls Count: #{calls}"
      counts[key] = calls
    end
    counts
  end

    def customer_params
      params.require(:customer).permit(
      :company, #会社名
      :name, #代表者
      :tel, #電話番号1
      :address, #住所
      :mobile, #携帯番号
      :industry, #業種
      :email, #メール
      :url, #URL
      :business, #
      :genre, #
      :contact_form,
      :contact_url,
      :fobbiden,
      :remarks, #履歴
      )
    end
end
