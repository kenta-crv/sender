class FormSubmissionsController < ApplicationController
  before_action :authenticate_admin!, except: [:import_customers, :index, :detect_contact_urls, :create, :show]
  before_action :authenticate_admin_or_client!, only: [:import_customers, :index, :detect_contact_urls, :create, :show]  
  before_action :set_batch, only: [:show, :cancel, :resume, :progress, :destroy]
  before_action :ensure_own_batch!, only: [:show, :cancel, :resume, :progress, :destroy]

  # GET /form_submissions
def index
    # -------------------------
    # 検索（Ransack）
    # -------------------------
    @q = Customer.ransack(params[:q])

    base_customers = @q.result
                       .includes(:last_form_call)
                       .distinct

    # -------------------------
    # 最新送信条件
    # -------------------------
    if params[:last_call].present?

      lc = params[:last_call]
      statuses = Array(lc[:status]).reject(&:blank?)

      has_filter =
        statuses.any? ||
        lc[:created_at_from].present? ||
        lc[:created_at_to].present?

      if has_filter

        customer_ids = Customer
          .includes(:last_form_call)
          .select do |customer|

            call = customer.last_form_call
            next false if call.blank?

            status_ok =
              statuses.blank? ||
              statuses.include?(call.status)

            from_ok =
              lc[:created_at_from].blank? ||
              call.created_at >= Time.zone.parse(lc[:created_at_from])

            to_ok =
              lc[:created_at_to].blank? ||
              call.created_at <= Time.zone.parse(lc[:created_at_to]).end_of_day

            status_ok && from_ok && to_ok
          end
          .map(&:id)

        base_customers = base_customers.where(id: customer_ids)
      end
    end

    # =====================================================
    # 顧客カテゴリ
    # =====================================================

    @customers = base_customers
                   .where.not(contact_url: [nil, '', 'not_detected'])
                   .page(params[:customers_page])
                   .per(50)

    # 【修正】business_filter / genre_filter を検出対象一覧にも適用する。
    # 旧実装ではこのクエリにフィルタが一切反映されておらず、
    # 業種・職種を選択しても画面の対象件数・一覧は常に全件のままだった
    # （POST側の detect_contact_urls アクションにしかフィルタが効いていなかった）。
    detectable_scope = base_customers
                          .where(contact_url: [nil, ''])
                          .where.not(url: [nil, ''])
                          .where(fobbiden: [nil, false, 0])

    detectable_scope = detectable_scope.where(business: params[:business_filter]) if params[:business_filter].present?
    detectable_scope = detectable_scope.where(genre: params[:genre_filter]) if params[:genre_filter].present?

    @detectable_customers = detectable_scope
                              .page(params[:detectable_page])
                              .per(50)

    @not_detected_count =
      Customer.where(contact_url: 'not_detected').count

    @no_url_customers =
      base_customers
        .where(contact_url: [nil, ''])
        .where(url: [nil, ''])

    @no_url_customers_count =
      @no_url_customers.count

    @submissions =
      Submission.order(created_at: :desc)

    @batches =
      FormSubmissionBatch
        .order(created_at: :desc)
        .page(params[:page])
        .per(20)

    @submission_stats =
      @submissions.map do |submission|

        batches =
          submission.form_submission_batches

        total_sent =
          batches.sum(:total_count)

        success_count =
          batches.sum(:success_count)

        failure_count =
          batches.sum(:failure_count)

        last_sent_at =
          batches
            .order(started_at: :desc)
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

    # =====================================================
    # 【追加項目】検索フォーム（ビュー）用の選択肢データ生成
    # =====================================================
    @business_options = Customer.where.not(business: [nil, '']).order(:business).pluck(:business).uniq
    @genre_options    = Customer.where.not(genre: [nil, '']).order(:genre).pluck(:genre).uniq
  end
  # POST /form_submissions
  def create
    # 送信対象のベーススコープ定義
    # クライアントがログインしている場合は、そのクライアントの顧客（または紐付けなし）に制限
    if admin_signed_in?
      eligible_scope = Customer.all
    elsif client_signed_in?
      eligible_scope = Customer.where(client_id: [current_client.id, nil])
    else
      eligible_scope = Customer.none
    end

    # 送信可能な条件（URLが存在し、禁止フラグが立っていないもの）
    eligible_scope = eligible_scope.where.not(contact_url: [nil, '', 'not_detected'])
                                   .where(fobbiden: [nil, false, 0])
                                   .order(:id)

    # 検索条件（Ransack）を適用
    if params[:q].present?
      eligible_scope = eligible_scope.ransack(params[:q]).result
    end

    # 最終送信条件を適用
    if params[:last_call].present?
      lc = params[:last_call]
      statuses = Array(lc[:status]).reject(&:blank?)
      has_filter = lc[:calls_id_null] == "true" ||
                   statuses.any? ||
                   lc[:created_at_from].present? ||
                   lc[:created_at_to].present?

      if has_filter
        eligible_scope = eligible_scope.left_joins(:calls).distinct
                           .where('calls.call_type IS NULL OR calls.call_type = ?', 'form')

        if lc[:calls_id_null] == "true"
          eligible_scope = eligible_scope.where(calls: { id: nil })
        end

        if statuses.any?
          eligible_scope = eligible_scope.where(calls: { status: statuses })
        end

        if lc[:created_at_from].present?
          eligible_scope = eligible_scope.where('calls.created_at >= ?', lc[:created_at_from])
        end

        if lc[:created_at_to].present?
          eligible_scope = eligible_scope.where('calls.created_at <= ?', lc[:created_at_to])
        end
      end
    end

    send_count = params[:send_count].to_i if params[:send_count].present?

    # チェックボックスで明示的に選択されたIDがある場合は、
    # 該当クライアントが所有している顧客レコードであるか最低限の検証のみ行い、eligible_scopeの強すぎる制約（Ransack等の不一致）をバイパスする
    customer_ids =
      if params[:select_all] == '1'
        eligible_scope.pluck(:id)
      elsif params[:customer_ids].present?
        # 選択されたIDが、ログイン中のクライアントがアクセス権を持つ顧客のものであるかを確認
        base_check = admin_signed_in? ? Customer.all : Customer.where(client_id: [current_client.id, nil])
        base_check.where(id: Array(params[:customer_ids]).map(&:to_i)).pluck(:id)
      elsif send_count && send_count > 0
        eligible_scope.limit(send_count).pluck(:id)
      else
        []
      end

    if send_count && send_count > 0 && customer_ids.size > send_count
      customer_ids = customer_ids.first(send_count)
    end

    # チェック後も対象が空の場合はアラートを出して戻す
    if customer_ids.empty?
      redirect_to client_signed_in? ? dashboard_index_path : form_submissions_path,
                  alert: '送信対象の顧客が選択されていません。件数を指定するか、顧客を選択してください。'
      return
    end

    # =========================
    # 月次制限チェック
    # Adminは制限なし
    # =========================
    client = current_client

    if client.present?
      unless client.can_send_this_month?(customer_ids.size)
        redirect_to client_signed_in? ? dashboard_index_path : form_submissions_path,
                    alert: "今月の送信上限に達しています（#{client.monthly_sent_count}/#{client.monthly_limit}）"
        return
      end
    end

    # バッチの作成
    batch = FormSubmissionBatch.create!(
      total_count: customer_ids.size,
      customer_ids: customer_ids.to_json,
      status: 'processing',
      started_at: Time.current,
      error_log: '[]',
      submission_id: params[:submission_id].presence,
      client: current_client,
      admin: current_admin
    )

    # =========================
    # 月次カウント加算
    # Adminは加算しない
    # =========================
    if client.present?
      client.increment_monthly_sent!(customer_ids.size)
    end

    # 並列処理: 各顧客を独立したジョブとしてキューに投入
    customer_ids.each do |cid|
      FormSendJob.perform_later(batch.id, cid)
    end

    # 遷移先の判定
    if client_signed_in? || admin_signed_in?
      redirect_to dashboard_index_path, notice: "バッチ送信を開始しました（#{customer_ids.size}件）"
    else
      redirect_to form_submission_path(batch), notice: "バッチ送信を開始しました（#{customer_ids.size}件）"
    end
  end

  def cleanup_duplicates
    attribute = params[:attribute]
    valid_attributes = %w[company tel url contact_url]

    unless valid_attributes.include?(attribute)
      if client_signed_in? && !admin_signed_in?
        return redirect_to dashboard_index_path, alert: "不正な属性指定です。"
      else
        return redirect_to form_submissions_path, alert: "不正な属性指定です。"
      end
    end

    # 1. ログイン状態に応じてベースとなるスコープを決定（ここを徹底します）
    base_scope = Customer.all
    if client_signed_in? && !admin_signed_in?
      base_scope = base_scope.where(client_id: current_client.id)
    end

    # 2. 決定した base_scope 内で、nil / 空文字 / 空白のみを除外して重複を抽出
    duplicate_values = base_scope
      .where.not(attribute => nil)
      .where.not("TRIM(#{attribute}) = ''")
      .group(attribute)
      .having("COUNT(id) > 1")
      .pluck(attribute)

    total_deleted = 0

    Customer.transaction do
      duplicate_values.each do |value|
        # 3. 決定した base_scope 内から、該当する値を持つIDを昇順で取得
        ids = base_scope.where(attribute => value).order(id: :asc).pluck(:id)

        # 先頭（最古）を残す
        ids.shift

        # 4. 該当レコードを物理削除（削除対象のID指定なのでここはCustomer全体からで安全です）
        deleted_records = Customer.where(id: ids).destroy_all
        total_deleted += deleted_records.size
      end
    end

    # 指定されたリダイレクト条件
    if client_signed_in? && !admin_signed_in?
      redirect_to dashboard_index_path,
                  notice: "#{attribute}の重複分 #{total_deleted} 件を削除しました。"
    else
      redirect_to form_submissions_path,
                  notice: "#{attribute}の重複分 #{total_deleted} 件を削除しました。"
    end
  end

  # GET /form_submissions/:id
  def show
    @results = Call.form_submissions
                   .where(customer_id: @batch.parsed_customer_ids)
                   .where('calls.created_at >= ?', @batch.created_at)
                   .order(created_at: :desc)
    @customers_by_id = Customer.where(id: @batch.parsed_customer_ids).index_by(&:id)
  end

  # PATCH /form_submissions/:id/cancel
  def cancel
    @batch.cancel!
    redirect_to form_submission_path(@batch), notice: 'バッチ送信をキャンセルしました。'
  end

  # POST /form_submissions/:id/resume
  def resume
    unprocessed = @batch.unprocessed_customer_ids

    if unprocessed.empty?
      redirect_to form_submission_path(@batch), alert: '未処理の顧客はありません。'
      return
    end

    # ステータスを処理中に戻し、合計件数を更新
    @batch.update!(
      status: 'processing',
      total_count: @batch.processed_count + unprocessed.size,
      completed_at: nil
    )

    # 未処理分のみ再キュー
    unprocessed.each do |cid|
      FormSendJob.perform_later(@batch.id, cid)
    end

    redirect_to form_submission_path(@batch), notice: "#{unprocessed.size}件の未処理分を再開しました。"
  end

  # GET /form_submissions/:id/progress (JSON)
  def progress
    response.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    render json: @batch.progress_payload
  end

  def update_manual
    @submission = Submission.find(params[:id])
    if @submission.update(manual: params[:manual] == '1')
      respond_to do |format|
        format.html { redirect_to form_submissions_path, notice: 'Manualフラグを更新しました。' }
        format.json { render json: { status: 'ok', manual: @submission.manual } }
      end
    else
      respond_to do |format|
        format.html { redirect_to form_submissions_path, alert: '更新に失敗しました。' }
        format.json { render json: { status: 'error' }, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    if @batch.destroy
      redirect_to form_submissions_path, notice: 'バッチ送信履歴を削除しました。'
    else
      redirect_to form_submissions_path, alert: '削除に失敗しました。'
    end
  end

def import_customers
    file = params[:file]

    if file.blank?
      if client_signed_in? && !admin_signed_in?
        redirect_to dashboard_index_path,
                    alert: 'CSVファイルを選択してください。'
      else
        redirect_to form_submissions_path,
                    alert: 'CSVファイルを選択してください。'
      end
      return
    end

    import_count = 0
    error_count = 0
    error_rows = []
    
    # 法人敬称をチェックするための正規表現パターン
    legal_entity_pattern = /株式会社|有限会社|合同会社|一般社団法人|一般財団法人|社会福祉法人|医療法人|学校法人|(株)|（株）|(有)|（有）|(同)|（同）/

    begin
      # headers: true により1行目をヘッダーとして扱う
      CSV.foreach(file.path, headers: true) do |row|
        # CSVのヘッダーが「会社名」か「company」のどちらでも動くように考慮
        company_name = row['会社名'] || row['company']
        
        # 会社名が空の場合はスキップまたはエラー
        if company_name.blank?
          error_count += 1
          error_rows << { row: row.to_h, errors: ["会社名(company)補正エラー"] }
          next
        end

        # 法人敬称が含まれているかチェック（含まれていない場合はエラーとしてスキップ）
        unless company_name.match?(legal_entity_pattern)
          error_count += 1
          error_rows << { row: row.to_h, errors: ["法人敬称（株式会社など）が含まれていません"] }
          next
        end

        customer = Customer.find_or_initialize_by(company: company_name)

        customer.assign_attributes(
          tel:          row['電話番号'] || row['tel'],
          address:      row['住所'] || row['address'],
          url:          row['HP URL'] || row['url'],
          email:        row['メールアドレス'] || row['email'],
          business:     row['業種'] || row['business'],
          genre:        row['職種'] || row['genre'],
          contact_url:  row['問い合わせURL'] || row['contact_url']
        )

        # client_id を紐付ける必要がある場合はここでセット
        customer.client_id = current_client.id if respond_to?(:current_client) && current_client

        if customer.save
          import_count += 1
        else
          error_count += 1
          error_rows << {
            row: row.to_h,
            errors: customer.errors.full_messages
          }
          Rails.logger.error("IMPORT ERROR: #{customer.errors.full_messages} | ROW: #{row.to_h}")
        end
      end

      message = "#{import_count}件の顧客をインポートしました。(失敗: #{error_count}件)"

      if error_rows.any?
        # 最初の3件ほどのエラー内容をアラートに表示する
        detail_errors = error_rows.first(3).map { |e| "[#{e[:row]['会社名'] || e[:row]['company']}] #{e[:errors].join(', ')}" }.join("\n")
        flash[:alert] = "一部のインポートに失敗しました:\n#{detail_errors}"
      end

      if client_signed_in? && !admin_signed_in?
        redirect_to dashboard_index_path, notice: message
      else
        redirect_to form_submissions_path, notice: message
      end

    rescue => e
      Rails.logger.error("IMPORT FATAL ERROR: #{e.message}\n#{e.backtrace.join("\n")}")

      if client_signed_in? && !admin_signed_in?
        redirect_to dashboard_index_path,
                    alert: "エラーが発生しました: #{e.message}"
      else
        redirect_to form_submissions_path,
                    alert: "エラーが発生しました: #{e.message}"
      end
    end
  end
  
  # POST /form_submissions/detect_contact_urls
# POST /form_submissions/detect_contact_urls
  def detect_contact_urls
    # Build base scope for customer selection
    base_scope = Customer.where(contact_url: [nil, ''])
                        .where.not(url: [nil, ''])
                        .where(fobbiden: [nil, false, 0])
    
    # Apply client filtering
    if client_signed_in? && !admin_signed_in?
      base_scope = base_scope.where(client_id: current_client.id)
    end
    
    # Apply business filter if provided
    if params[:business_filter].present?
      base_scope = base_scope.where(business: params[:business_filter])
    end

    # 【追加】職種(genre)フィルタにも対応
    if params[:genre_filter].present?
      base_scope = base_scope.where(genre: params[:genre_filter])
    end

    customer_ids = if params[:detect_select_all] == '1'
                     # 全件選択 → ページネーションに関係なく全対象顧客を取得
                     base_scope.pluck(:id)
                   else
                     # customer_ids parameter is sent as array from checkbox inputs
                     Array(params[:customer_ids]).map(&:to_i)
                   end

    if customer_ids.empty?
      if client_signed_in? && !admin_signed_in?
        redirect_to dashboard_index_path, alert: '検出対象の顧客が選択されていません。'
      else
        redirect_to form_submissions_path, alert: '検出対象の顧客が選択されていません。'
      end
      return
    end

    # サブスクリプション制限チェック（Clientの場合）
    if client_signed_in? && !admin_signed_in?
      monthly_log = current_client.monthly_usage_log
      subscription_remaining = [monthly_log.form_detection_limit - monthly_log.form_detection_used, 0].max

      if subscription_remaining <= 0
        redirect_to dashboard_index_path, alert: "今月のフォーム検出使用上限に達しています（#{monthly_log.form_detection_used}/#{monthly_log.form_detection_limit}）"
        return
      end

      # リクエストされた件数が残り上限を超えている場合は制限する
      if customer_ids.size > subscription_remaining
        customer_ids = customer_ids.first(subscription_remaining)
        redirect_to dashboard_index_path, alert: "残り上限（#{subscription_remaining}件）を超えているため、#{subscription_remaining}件のみ処理します。"
        return
      end

      # 使用数を加算
      monthly_log.increment!(:form_detection_used, customer_ids.size)
    end

    # Create batch for form detection
    batch = FormDetectionBatch.create!(
      total_count: customer_ids.size,
      customer_ids: customer_ids.to_json,
      status: 'processing',
      started_at: Time.current,
      client: current_client,
    )

    # 並列処理: 各顧客を独立したジョブとしてキューに投入
    customer_ids.each do |cid|
      ContactUrlDetectJob.perform_later(cid, batch.id)
    end
    redirect_to dashboard_index_path, notice: "#{customer_ids.size}件のお問い合わせフォームURL自動検出を開始しました。"
  end
  
  private

  def set_batch
    @batch = FormSubmissionBatch.find(params[:id])
  end

  # バッチデータの所有権・閲覧権限を検証する認可フィルター
  def ensure_own_batch!
    return if admin_signed_in? # 管理者は全件アクセスを許可

    # クライアントログイン時に、対象バッチの所有クライアントIDと一致するかチェック
    if client_signed_in? && @batch.client_id == current_client.id
      return
    end

    # 権限がない、または一致しない場合はダッシュボードへリダイレクトして閲覧を遮断
    redirect_to dashboard_index_path, alert: '指定されたページへのアクセス権限がありません。'
  end

  def authenticate_admin_or_client!
    unless admin_signed_in? || client_signed_in?
      redirect_to new_admin_session_path, alert: 'ログインしてください'
    end
  end
end