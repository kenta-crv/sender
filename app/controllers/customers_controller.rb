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

  def new
    @customer = Customer.new
  end

  #def search
 #  branch = params[:branch]
 #   address = params[:address]
 #   @customers = Customer.where(branch: branch, address: address)
 # end

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
  if @customer.remarks.blank?
    @customer.remarks = <<~TEXT
      ①まず冒頭で恐れ入りますが、現在も御社は人材は募集している形でお間違いなかったでしょうか？
      →

      ②御社で成功報酬等が無く採用ができるなら、人材の質によっては特定技能外国人材でのすぐ面接まで対応いただくことは可能でしょうか？
      →

      ③もう一点、無料となるとご警戒されてしまうと思うので確認となりますが、『特定技能外国人』自体についての仕組みはご存知でしょうか？
      →

      赤枠内の説明可否
      → 説明済・未説明

      【備考】
    TEXT
  end

  if worker_signed_in?
    @q = Customer.where(status: "draft").where("TRIM(tel) = ''")
    @customers = @q.ransack(params[:q]).result.page(params[:page]).per(100)
  end
end

def update
  @customer = Customer.find(params[:id])

  # 🌟 worker がログインしている場合、初回更新者をセット
  if worker_signed_in? && current_worker.present?
    @customer.assign_first_editor(current_worker) if @customer.respond_to?(:assign_first_editor)
  end

  # 対象外リスト or 公開
  if params[:commit] == '対象外リストとして登録'
    @customer.skip_validation = true if @customer.respond_to?(:skip_validation=)
    @customer.status = "hidden"
    @customer.save(validate: false)
  elsif params[:commit] == '公開して一覧へ'
    @customer.status = nil
    @customer.save(validate: false)
    redirect_to customers_path(
      q: params[:q]&.permit!,
      industry_name: params[:industry_name],
      tel_filter: params[:tel_filter]
    ) and return
  end

  # admin または user の場合も普通に update
  if admin_signed_in? || user_signed_in?
    saved = @customer.update(customer_params)
  else
    saved = @customer.update(customer_params)
  end

  # 次の draft 顧客を取得（フィルタ考慮）
  @q = Customer.where(status: 'draft').where('id > ?', @customer.id)
  @q = @q.where(industry: params[:industry_name]) if params[:industry_name].present?

  case params[:tel_filter]
  when "with_tel"
    @q = @q.where.not("TRIM(tel) = ''")
  when "without_tel"
    @q = @q.where("TRIM(tel) = ''")
  end

  @next_draft = @q.order(:id).first

  if saved
    # メール送信
    if params[:commit] == '登録＋J Workメール送信'
      CustomerMailer.teleapo_send_email(@customer, current_user).deliver_now
      CustomerMailer.teleapo_reply_email(@customer, current_user).deliver_now
    elsif params[:commit] == '資料送付'
      CustomerMailer.document_send_email(@customer, current_user).deliver_now
      CustomerMailer.document_reply_email(@customer, current_user).deliver_now
    end

    # workerリダイレクト
    if worker_signed_in?
      if @next_draft
        redirect_to edit_customer_path(
          id: @next_draft.id,
          industry_name: params[:industry_name],
          tel_filter: params[:tel_filter]
        )
      else
        redirect_to request.referer, notice: 'リストが終了しました。リスト追加を行いますので、管理者に連絡してください。'
      end
    else
      redirect_to customer_path(
        id: @customer.id,
        q: params[:q]&.permit!,
        last_call: params[:last_call]&.permit!
      )
    end
  else
    render 'edit'
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

  def information
    @calls = Call.joins(:customer)
    @customers =  Customer.all
    @admins = Admin.all
    @users = User.all
    @customers_app = @customers.where(call_id: 1)
      #today
      @call_today_basic = @calls.where(status: ["着信留守", "担当者不在","フロントNG","見込","APP","NG","クロージングNG","受付NG","自己紹介NG","質問段階NG","日程調整NG"])
                          .where('calls.created_at > ?', Time.current.beginning_of_day)
                          .where('calls.created_at < ?', Time.current.end_of_day)
                          .to_a
      @call_count_today = @call_today_basic.count
      @protect_count_today = @call_today_basic.select { |call| call.status == "見込" }.count
      @protect_convertion_today = (@protect_count_today.to_f / @call_count_today.to_f) * 100
      @app_count_today = @call_today_basic.select { |call| call.status == "APP" }.count
      @app_convertion_today = (@app_count_today.to_f / @call_count_today.to_f) * 100

      #week
      @call_week_basic = @calls.where(status: ["着信留守", "担当者不在","フロントNG","見込","APP","NG","クロージングNG","受付NG","自己紹介NG","質問段階NG","日程調整NG"])
      .where('calls.created_at > ?', Time.current.beginning_of_week)
      .where('calls.created_at < ?', Time.current.end_of_week)
      .to_a
      @call_count_week = @call_week_basic.count
      @protect_count_week = @call_week_basic.select { |call| call.status == "見込" }.count
      @protect_convertion_week = (@protect_count_week.to_f / @call_count_week.to_f) * 100
      @app_count_week = @call_week_basic.select { |call| call.status == "APP" }.count
      @app_convertion_week = (@app_count_week.to_f / @call_count_week.to_f) * 100

      #month
      @call_month_basic = @calls.where(status: ["着信留守", "担当者不在","フロントNG","見込","APP","NG","クロージングNG","受付NG","自己紹介NG","質問段階NG","日程調整NG"])
      .where('calls.created_at > ?', Time.current.beginning_of_month)
      .where('calls.created_at < ?', Time.current.end_of_month)
      .to_a
      @call_count_month = @call_month_basic.count
      @protect_count_month = @call_month_basic.select { |call| call.status == "見込" }.count
      @protect_convertion_month = (@protect_count_month.to_f / @call_count_month.to_f) * 100
      @app_count_month = @call_month_basic.select { |call| call.status == "APP" }.count
      @app_convertion_month = (@app_count_month.to_f / @call_count_month.to_f) * 100

      #  ステータス別結果
      @call_count_called = @call_month_basic.select { |call| call.status == "着信留守" }
      @call_count_absence = @call_month_basic.select { |call| call.status == "担当者不在" }
      @call_count_prospect = @call_month_basic.select { |call| call.status == "見込" }
      @call_count_app = @call_month_basic.select { |call| call.status == "APP" }
      @call_count_cancel = @call_month_basic.select { |call| call.status == "キャンセル" }
      @call_count_ng = @call_month_basic.select { |call| call.status == "NG" }

      # 企業別アポ状況
      @customer2_sorairo = Customer2.where("industry LIKE ?", "%SORAIRO%")
      @customer2_takumi = Customer2.where("industry LIKE ?", "%アポ匠%")
      @customer2_omg = Customer2.where("industry LIKE ?", "%OMG%")
      @customer2_kousaido = Customer2.where("industry LIKE ?", "%廣済堂%")
      @detail_sorairo = @customer2_sorairo.calls.where("created_at > ?", Time.current.beginning_of_month).where("created_at < ?", Time.current.end_of_month).to_a if @detail_sorairo.present?
      @detail_takumi = @customer2_takumi.calls.where("created_at > ?", Time.current.beginning_of_month).where("created_at < ?", Time.current.end_of_month).to_a if @detail_takumi.present?
      @detail_omg = @customer2_omg.calls.where("created_at > ?", Time.current.beginning_of_month).where("created_at < ?", Time.current.end_of_month).to_a if @detail_omg.present?
      @detail_kousaido = @customer2_kousaido.calls.where("created_at > ?", Time.current.beginning_of_month).where("created_at < ?", Time.current.end_of_month).to_a if @detail_kousaido.present?

      @admins = Admin.all
      @users = User.all

      @detailcalls = Customer2.joins(:calls).select('calls.id')
      @detailcustomers = Call.joins(:customer).select('customers.id')

      @app_customers_last_month = Call.joins(:customer).where('calls.created_at >= ? AND calls.created_at < ?', Time.current.prev_month.beginning_of_month, Time.current.beginning_of_month).select('customers.id')
      @app_customers_last_month_total_industry_value = @app_customers_last_month.present? ? @app_customers_last_month.sum(:industry_code) : 0

      @app_customers = Call.joins(:customer).where('calls.created_at > ?', Time.current.beginning_of_month).where('calls.created_at < ?', Time.current.end_of_month).select('customers.id')
      @app_customers_total_industry_value = @app_customers.present? ? @app_customers.sum(:industry_code) : 0

      @industry_mapping = Customer::INDUSTRY_MAPPING
      @app_calls_counts = calculate_app_calls_counts

      @industries_data = INDUSTRY_ADDITIONAL_DATA.keys.map do |industry_name|
        Customer.analytics_for(industry_name)
      end    

      @companies_data = INDUSTRY_ADDITIONAL_DATA.keys.map do |company_name|
        Customer.analytics2_for(company_name)
      end.group_by { |data| data[:company_name] }
         .map do |company_name, records|
           # 同じcompany_nameが存在する場合、そのデータをまとめる
           first_record = records.first
      
           # もし必要であれば、複数の同じcompany_nameのデータを合算
           combined_data = {
             company_name: first_record[:company_name],
             industry_code: first_record[:industry_code],
             industry_name: first_record[:industry_name],
             list_count: records.sum { |record| record[:list_count] || 0 },
             call_count: records.sum { |record| record[:call_count] || 0 },
             app_count: records.sum { |record| record[:app_count] || 0 },
             payment_date: first_record[:payment_date] # 日付は一番最初のデータを使用
           }
           combined_data
         end
  end

  def news
    @customers =  Customer.all
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


      

  def print
    report = Thinreports::Report.new layout: "app/reports/layouts/invoice.tlf"
    
    @companies_data = INDUSTRY_ADDITIONAL_DATA.keys.map do |company_name|
      Customer.analytics2_for(company_name)
    end.group_by { |data| data[:company_name] }
    .map do |company_name, records|
      first_record = records.first
      combined_data = {
        company_name: first_record[:company_name],
        industry_code: first_record[:industry_code],
        industry_name: first_record[:industry_name],
        list_count: records.sum { |record| record[:list_count] || 0 },
        call_count: records.sum { |record| record[:call_count] || 0 },
        app_count: records.sum { |record| record[:app_count] || 0 },
        payment_date: first_record[:payment_date]
      }
      combined_data
    end  
    @companies_data.each do |data|
      create_pdf_page(report, data)
    end
    send_data(report.generate, filename: "industries_report_#{Time.zone.now.to_formatted_s(:number)}.pdf", type: "application/pdf")
  end
  
  def generate_pdf
    company_name = params[:company_name]
    @companies_data ||= INDUSTRY_ADDITIONAL_DATA.keys.map do |name|
      Customer.analytics2_for(name)
    end.group_by { |data| data[:company_name] }
    .map do |company_name, records|
      first_record = records.first
      combined_data = {
        company_name: first_record[:company_name],
        industry_code: first_record[:industry_code],
        industry_name: first_record[:industry_name],
        list_count: records.sum { |record| record[:list_count] || 0 },
        call_count: records.sum { |record| record[:call_count] || 0 },
        app_count: records.sum { |record| record[:app_count] || 0 },
        payment_date: first_record[:payment_date]
      }
      combined_data
    end
    data = @companies_data.find { |d| d[:company_name] == company_name }
    if data.nil?
      Rails.logger.error("No data found for industry name: #{company_name}")
      return
    end
    report = Thinreports::Report.new layout: 'app/reports/layouts/invoice.tlf'
    create_pdf_page(report, data)
    send_data report.generate, filename: "#{company_name}.pdf", type: 'application/pdf', disposition: 'attachment'
  end
  
  def thinreports_email
    company_name = params[:company_name]
    Rails.logger.info("Looking for customer with company_name: #{company_name}")
  
    # @companies_dataの取得と処理
    @companies_data ||= INDUSTRY_ADDITIONAL_DATA.keys.map do |name|
      Customer.analytics2_for(name)
    end
  
    data = @companies_data.find { |d| d[:company_name] == company_name }
    app_count_customers = data[:app_count_customers]
  
    app_count_customers.each do |customer|
      customer.calls.where(status: "APP").each do |call|
        puts "Company: #{customer.company}, Call Created At: #{call.created_at}"
      end
    end
    # 顧客情報の取得とindustry_mailの確認
    customer = Customer.where("company_name LIKE ?", "%#{company_name}%").first
    industry_mail = customer.industry_mail
  
    # ThinreportsでPDFを作成
    report = Thinreports::Report.new layout: 'app/reports/layouts/invoice.tlf'
    create_pdf_page(report, data)  # PDF作成メソッドを利用
    pdf_content = report.generate
  
    # メール送信、データも渡す
    CustomerMailer.send_thinreports_data(industry_mail, data, pdf_content).deliver_now  
    redirect_to customers_path, notice: "メールが送信されました"
  end
  
  def jwork
    @customers = Customer
      .where("customers.industry LIKE ?", "%J Work%")
      .joins(:calls)
      .where(calls: { status: "APP" })
      .distinct
      .includes(:calls)
  end
    
  def documents
    customer = Customer.find_by(id: params[:from]) # クエリで顧客IDを受け取る
  
    if customer
      # アクセスログ保存
      AccessLog.create!(
        customer: customer,
        path: request.path,
        ip: request.remote_ip,
        accessed_at: Time.current
      )
  
      # 管理者に通知メール送信
      CustomerMailer.clicked_notice(customer).deliver_later
    end
  
    pdf_path = Rails.root.join('public', 'documents.pdf')
    if File.exist?(pdf_path)
      send_file pdf_path, filename: 'documents.pdf', type: 'application/pdf', disposition: 'attachment'
    else
      render plain: 'ファイルが見つかりません', status: 404
    end
  end
  

  def calculate
    user = User.find(params[:user_id])
    input_val = params[:input_val].to_i
    user_calls_count = user.calls.where('created_at > ?', Time.current.beginning_of_month).where('created_at < ?', Time.current.end_of_month).count
    answer = user_calls_count / input_val.to_f
    answer = answer.nan? ? 0 : answer
    render json: { answer: answer.round(2) }
  end

def draft
  start_time = Time.current

  # 期間パラメータの解釈（未指定可）
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

  # 期間の整合性（逆転していたら入れ替え）
  if @period_start.present? && @period_end.present? && @period_end < @period_start
    @period_start, @period_end = @period_end, @period_start
  end

  range_start = @period_start&.beginning_of_day
  range_end   = @period_end&.end_of_day

  # SERP補完対象候補を表示する一覧。
  # 取引先環境で status カラムは別用途に使われているため、
  # 必須条件は serp_status（NULL/serp_queued/serp_done/serp_imported/serp_error）に変更。
  # status="draft" は任意フィルタとしてのみ適用可能。
  visible_serp_statuses = if params[:serp_status_filter] == "serp_imported"
                            ["serp_imported"]
                          else
                            [nil, '', 'serp_queued', 'serp_done', 'serp_error']
                          end
  draft_base = Customer.where(serp_status: visible_serp_statuses)

  if admin_signed_in?
    # Adminは全件表示
  elsif client_signed_in?
    draft_base = draft_base.where(client_id: current_client.id)
  end

  draft_base = draft_base.where(status: params[:status_filter]) if params[:status_filter].present?

  # serp_status での絞り込み（"null" は NULL/'' を表す）
  case params[:serp_status_filter]
  when "null"
    draft_base = filter_effective_serp_unprocessed(draft_base)
  when "serp_queued", "serp_done", "serp_imported", "serp_error"
    draft_base = params[:serp_status_filter] == "serp_done" ? filter_effective_serp_done(draft_base) : draft_base.where(serp_status: params[:serp_status_filter])
  end

  # Adminを優先した条件分岐（tel_filter は従来通り）
  @customers = case
  when admin_signed_in? && params[:tel_filter] == "with_tel"
    draft_base.where.not(tel: [nil, '', ' '])
  when admin_signed_in? && params[:tel_filter] == "without_tel"
    draft_base.where(tel: [nil, '', ' '])
  when worker_signed_in?
    draft_base.where(tel: [nil, '', ' '])
  else
    draft_base
  end

  @company_query = params[:company_query].to_s.strip
  @customers = filter_company_query(@customers, @company_query)

  # 充足条件フィルタ: 例 "missing_tel" → tel 未取得のみ
  case params[:fill_filter]
  when "missing_tel"
    @customers = @customers.where("tel IS NULL OR TRIM(tel) = ''")
  when "missing_address"
    @customers = @customers.where("address IS NULL OR TRIM(address) = ''")
  when "missing_url"
    @customers = filter_missing_official_url(@customers)
  when "missing_contact_url"
    @customers = @customers.where("contact_url IS NULL OR TRIM(contact_url) = ''")
  when "partial_address"
    @customers = filter_partial_address(@customers)
  when "fully_enriched"
    @customers = filter_detailed_address(
      filter_official_url(
        @customers.where.not(tel: [nil, '', ' '])
                  .where.not(contact_url: [nil, '', ' '])
      )
    )
  when "done_missing_tel"
    @customers = filter_effective_serp_done(@customers).where("tel IS NULL OR TRIM(tel) = ''")
  when "done_missing_address"
    @customers = filter_effective_serp_done(@customers).where("address IS NULL OR TRIM(address) = ''")
  when "done_partial_address"
    @customers = filter_partial_address(filter_effective_serp_done(@customers))
  end

  # 最終更新日のフィルタ
  # 優先順位: updated_from / updated_to が指定されていればそれを使用、
  # それ以外で updated_today=1 なら本日のみ。
  updated_from = (Date.parse(params[:updated_from]) rescue nil) if params[:updated_from].present?
  updated_to   = (Date.parse(params[:updated_to])   rescue nil) if params[:updated_to].present?
  if updated_from || updated_to
    if updated_from && updated_to
      @customers = @customers.where(updated_at: zoned_beginning_of_day(updated_from)..zoned_end_of_day(updated_to))
    elsif updated_from
      @customers = @customers.where("updated_at >= ?", zoned_beginning_of_day(updated_from))
    else
      @customers = @customers.where("updated_at <= ?", zoned_end_of_day(updated_to))
    end
  elsif params[:updated_today] == "1"
    @customers = @customers.where(updated_at: zoned_today_range)
  end

  # 期間でフィルタ（未指定なら全期間）
  if range_start && range_end
    @customers = @customers.where(created_at: range_start..range_end)
  elsif range_start
    @customers = @customers.where('created_at >= ?', range_start)
  elsif range_end
    @customers = @customers.where('created_at <= ?', range_end)
  end

  # 業種でフィルタ
  if params[:industry_name].present?
    @customers = @customers.where(industry: params[:industry_name])
  end

  @filtered_count = @customers.count
  @customers = @customers.order(updated_at: :desc).page(params[:page]).per(100)

  # 残り件数取得
  today_total = ExtractTracking
                  .where(created_at: zoned_today_range)
                  .sum(:total_count)

  daily_limit = ENV.fetch('EXTRACT_DAILY_LIMIT', '500').to_i
  @remaining_extractable = [daily_limit - today_total, 0].max

  # SERP補完対象件数（serp_status ベース: URL/TELがどちらも空の会社のみ）
  serp_scope = if @company_query.present?
                 BrightData::Pipeline.serp_target_scope.where(serp_status: [nil, '', 'serp_done', 'serp_error'])
               else
                 BrightData::Pipeline.serp_target_scope.where(serp_status: [nil, ''])
               end
  serp_scope = serp_scope.where(client_id: current_client.id) if client_signed_in? && !admin_signed_in?
  serp_scope = serp_scope.where(industry: params[:industry_name]) if params[:industry_name].present?
  serp_scope = filter_company_query(serp_scope, @company_query)
  @serp_target_count = serp_scope.count
  @redis_reachable = redis_reachable?
  @redis_auto_start_possible = redis_auto_start_possible?
  @serp_worker_running = serp_worker_running?
  @serp_queue_size = serp_queue_size
  @serp_progress = current_serp_progress_payload

  # ── ダッシュボードサマリー ──
  # SERP補完対象になり得る範囲（status カラムを参照しない）を母集団にする。
  dash_statuses = params[:serp_status_filter] == "serp_imported" ? ["serp_imported"] : [nil, '', 'serp_queued', 'serp_done', 'serp_error']
  dash_scope = Customer.where(serp_status: dash_statuses)
  dash_scope = dash_scope.where(client_id: current_client.id) if client_signed_in? && !admin_signed_in?
  dash_scope = dash_scope.where(industry: params[:industry_name]) if params[:industry_name].present?
  dash_scope = filter_company_query(dash_scope, @company_query)

  total = dash_scope.count
  status_counts = dash_scope.group(:serp_status).count
  null_c     = filter_effective_serp_unprocessed(dash_scope).count
  queued_c   = status_counts["serp_queued"].to_i
  done_c     = filter_effective_serp_done(dash_scope).count
  imported_c = status_counts["serp_imported"].to_i
  error_c    = status_counts["serp_error"].to_i

  tel_c     = dash_scope.where.not(tel: [nil, '', ' ']).count
  addr_c    = detailed_address_count(dash_scope)
  url_c     = official_url_count(dash_scope)
  contact_c = dash_scope.where.not(contact_url: [nil, '', ' ']).count
  full_c    = detailed_address_count(
    filter_official_url(
      dash_scope.where.not(tel: [nil, '', ' '])
                .where.not(contact_url: [nil, '', ' '])
    )
  )

  @dashboard_stats = {
    total: total,
    status: {
      null: null_c, queued: queued_c, done: done_c, imported: imported_c, error: error_c
    },
    fill: {
      tel: tel_c, address: addr_c, url: url_c, contact_url: contact_c, full: full_c
    }
  }

  elapsed = ((Time.current - start_time) * 1000).round(2)
  Rails.logger.info("draft action: completed in #{elapsed}ms")
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

    # 同期実行に変更
    # ExtractCompanyInfoWorker.perform_async(tracking.id)
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

  # SERP APIによる情報補完実行（UIから起動）
  def serp_search
    industry  = params[:industry].presence
    company_query = params[:company_query].to_s.strip
    limit     = [(params[:limit] || 100).to_i, 1].max

    # 対象件数を事前確認（URL/TELがどちらも空の会社のみ）
    scope = if company_query.present?
              BrightData::Pipeline.serp_target_scope.where(serp_status: [nil, '', 'serp_done', 'serp_error'])
            else
              BrightData::Pipeline.serp_target_scope.where(serp_status: [nil, ''])
    end
    scope = scope.where(industry: industry) if industry.present?
    scope = scope.where(client_id: current_client.id) if client_signed_in? && !admin_signed_in?
    scope = filter_company_query(scope, company_query)
    target_count = scope.count

    if target_count == 0
      redirect_to draft_customers_path, alert: "SERP補完の対象データが存在しません。" and return
    end

    # Sidekiq経由で非同期実行。UI実行では同期処理へ逃がさず、
    # Redis/Sidekiq の準備が取れた場合だけジョブを投入する。
    if ENV["BRIGHT_DATA_API_KEY"].to_s.strip.blank?
      redirect_to draft_customers_path,
        alert: "BRIGHT_DATA_API_KEY が未設定です。.env を確認し、Rails/Sidekiqを再起動してから再実行してください。" and return
    end

    actual_limit = [limit, target_count].min
    selected_targets = scope.order(updated_at: :desc, id: :asc)
                            .limit(actual_limit)
                            .select(:id, :company, :serp_status, :tel, :address, :url, :contact_url)
                            .to_a
    target_ids = selected_targets.map(&:id)
    actual_limit = target_ids.size

    if actual_limit == 0
      redirect_to draft_customers_path, alert: "SERP補完の対象データが存在しません。" and return
    end

    sidekiq = SerpSidekiqManager.ensure_running
    unless sidekiq.ready?
      redirect_to draft_customers_path, alert: sidekiq.message and return
    end

    begin
      progress_run_id = SecureRandom.hex(12)
      audit_run = SerpEnrichmentRun.create_for_targets!(
        run_id: progress_run_id,
        industry: industry,
        limit: actual_limit,
        targets: selected_targets
      )
      SerpProgressTracker.start(
        run_id: progress_run_id,
        total: actual_limit,
        industry: industry,
        target_ids: target_ids
      )
      session[:serp_progress_run_id] = progress_run_id
      jid = SerpPipelineDbWorker.perform_async(industry, actual_limit, target_ids, progress_run_id)
      audit_run.update!(jid: jid.to_s) if jid.present?
      redirect_to draft_customers_path
    rescue Redis::CannotConnectError, Errno::ECONNREFUSED => e
      Rails.logger.warn("[serp_search] Redis接続不可: #{e.message}")
      redirect_to draft_customers_path,
        alert: "Redisに接続できないため、SERP補完を開始できませんでした。Redisを起動してから再実行してください。"
    end
  end

  def serp_progress
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'

    render json: current_serp_progress_payload
  end

  # 進捗取得API（ポーリング用）
  # GET /draft/progress.json?industry=業界名
  # industryパラメータが指定されていない場合、全業種の進捗を返す
  def extract_progress
    # ポーリング用のため、キャッシュを無効化
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    response.headers['Pragma'] = 'no-cache'
    response.headers['Expires'] = '0'
    
    industry = params[:industry].to_s.presence
    
    if industry
      # 後方互換性のため、industryパラメータが指定されている場合は既存の動作を維持
      tracking = ExtractTracking.where(industry: industry).order(id: :desc).first
      if tracking
        render json: tracking.progress_payload
      else
        render json: { message: 'no_tracking' }
      end
    else
      # 全業種の進捗を返す（N+1クエリを回避）
      crowdworks = Crowdwork.all || []
      industry_names = crowdworks.map(&:title)
      
      # 各業種の最新のtrackingを一括取得
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


  def filter_by_industry
    # crowdworkタイトルの初期化
    @crowdworks = Crowdwork.all || []

    # 期間パラメータの解釈（未指定可）
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

    # 期間の整合性（逆転していたら入れ替え）
    if @period_start.present? && @period_end.present? && @period_end < @period_start
      @period_start, @period_end = @period_end, @period_start
    end
    range_start = @period_start&.beginning_of_day
    range_end   = @period_end&.end_of_day

    # タイトルによるフィルタリング
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

    # Adminを優先した条件分岐
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

    # タイトルごとの件数を計算（期間条件があれば適用）
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

    # ExtractTrackingを一括取得してN+1を回避（SQLite対応）
    industry_names = @crowdworks.map(&:title)
    all_trackings = ExtractTracking.where(industry: industry_names).order(id: :desc)
    # Ruby側で各業種の最新のtrackingを取得
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

    # ページネーション
    @customers = @customers.page(params[:page]).per(100)

    # 残り件数取得
    today_total = ExtractTracking
                    .where(created_at: Time.current.beginning_of_day..Time.current.end_of_day)
                    .sum(:total_count)
    daily_limit = ENV.fetch('EXTRACT_DAILY_LIMIT', '500').to_i
    @remaining_extractable = [daily_limit - today_total, 0].max

    render :draft
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

      existing_customer = Customer.where(industry: customer.industry, status: nil) # 公開中のみ
                                  .where.not(id: customer.id)
                                  .find do |c|
        # 電話番号比較（ハイフン無視）
        c_tel = c.tel.to_s.delete('-')
        tel_match = normalized_tel.present? && c_tel.present? && normalized_tel == c_tel

        # 会社名比較（法人格除去後、3文字以上一致）
        c_company = Customer.normalized_name(c.company)
        name_match = Customer.name_similarity?(normalized_company, c_company)

        tel_match || name_match
      end

      if existing_customer
        latest_call = existing_customer.calls.order(created_at: :desc).first

        if latest_call && latest_call.created_at <= 2.months.ago
          # APP・永久NG・見込 の場合は再掲載しない
          unless %w(APP 永久NG 見込).include?(latest_call.status)
            existing_customer.calls.create(status: '再掲載')

            if customer.worker.present?
              customer.worker.increment!(:deleted_customer_count)
            end

            customer.destroy
            reposted_count += 1
            next
          end
        end

        # 再掲載しない場合は単純削除
        if customer.worker.present?
          customer.worker.increment!(:deleted_customer_count)
        end

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

  # nil / 空文字 / 空白のみ をすべて除外
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

      # 先頭（最古）を残す
      ids.shift

      deleted_records = Customer.where(id: ids).destroy_all
      total_deleted += deleted_records.size
    end
  end

  redirect_to request.referer || form_submissions_path,
              notice: "#{attribute}の重複分 #{total_deleted} 件を削除しました。"
end
      
  private

  def authenticate_admin_or_client!
    # deviseなどを使用している場合の例
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
    terms = query.to_s.strip.split(/[[:space:]　]+/).reject(&:blank?)
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

  def filter_effective_serp_done(scope)
    scope.where(
      "serp_status = ? OR ((serp_status IS NULL OR serp_status = '') AND (#{Customer::TEL_OR_URL_PRESENT_SQL}))",
      "serp_done"
    )
  end

  def filter_effective_serp_unprocessed(scope)
    scope.where(serp_status: [nil, ""]).merge(Customer.without_tel_and_url)
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

  def create_pdf_page(report, data)
    customer = @customer
    report.start_new_page do |page|

      company_name = data[:company_name]
      start_of_month = Time.current.beginning_of_month
      end_of_month = Time.current.end_of_month
      app_count = data[:app_count]
      # 現在の日時を取得し、指定の形式にフォーマット
      current_time = Time.now.strftime('%Y年%m月%d日')  
      # 合計値の計算
      industry_code = data[:industry_code]
      total = (data[:industry_code] * data[:app_count])
      # 税金の計算（合計値の10%とする）
      tax = (total * 0.10).to_i
      # 税込み合計値の計算
      all = (total + tax).to_i
      formatted_all = all.to_s.gsub(/(\d)(?=(\d{3})+(?!\d))/, '\1,')
      # 支払い月の計算（翌月の年月
      next_month = Time.now.next_month.strftime('%Y年%m月')
      payment_month = "#{next_month}#{data[:payment_date]}"
  
      page.values(
        company_name: company_name, # 会社名
        created_at: current_time, # 発行日
        app_count: app_count, # アポカウント
        industry_code: industry_code, # 単価
        total: total, # 税抜合計
        total_1: total, # 税抜合計
        total_2: total, # 税抜合計
        all: formatted_all, # 税込み合計
        all_1: all, # 税込み合計
        tax_price: tax, # 税抜合計
        payment: payment_month, # 支払い月        
      )
    end
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
