class Customer < ApplicationRecord
  has_many :calls, dependent: :destroy  
  has_one :last_call, -> { order(created_at: :desc) }, class_name: 'Call'
  has_one :last_form_call, -> { where(call_type: 'form').order(created_at: :desc) }, class_name: 'Call'
  belongs_to :worker, optional: true#これがあるとインポートもCreateも通らない
  belongs_to :client, optional: true
  before_create :generate_unsubscribe_token
  scope :between_created_at, ->(from, to){
    where(created_at: from..to).where.not(tel: nil)
  }
  scope :between_called_at, ->(from, to){
    where(created_at: from..to)
  }


  scope :ltec_calls_count, ->(count){
    filter_ids = joins(:calls).group("calls.customer_id").having('count(*) <= ?',count).count.keys
    where(id: filter_ids)
  }
    # Ransack で検索可能な関連を明示
  def self.ransackable_associations(auth_object = nil)
    %w[calls last_call]
  end

  # Ransack で検索可能なカラムを明示（必要に応じて）
  def self.ransackable_attributes(auth_object = nil)
    %w[
      company      # 会社名
      name         # 代表者
      tel          # 電話番号1
      address      # 住所
      mobile       # 携帯番号
      industry     # 業種
      email        # メール
      url          # URL
      business     # 業種詳細
      genre        # 職種
      contact_url # 問い合わせフォーム
      remarks      # 備考
      fobbiden
      contact_url  # お問い合わせフォームURL
      created_at
      updated_at
      id
    ]
  end


  def generate_unsubscribe_token
    self.unsubscribe_token ||= SecureRandom.hex(32)
  end

  # 基本的なドラフトデータ対象 + 閲覧制限・業種フィルタの基礎スコープ
  def self.draft_base_scope(current_client_id: nil, is_admin: false, industry_name: nil)
    scope = where(serp_status: [nil, '', 'serp_queued', 'serp_done', 'serp_imported', 'serp_error'])
    
    if is_admin
      # 管理者は全件
    elsif current_client_id.present?
      scope = scope.where(client_id: current_client_id)
    else
      scope = scope.none
    end

    scope = scope.where(industry: industry_name) if industry_name.present?
    scope
  end

  # 通常ステータスフィルタ
  def self.apply_status_filter(status)
    status.present? ? where(status: status) : all
  end

  # SERPステータスフィルタ
  def self.apply_serp_status_filter(serp_status)
    case serp_status
    when "null"
      where(serp_status: [nil, ''])
    when "serp_queued", "serp_done", "serp_imported", "serp_error"
      where(serp_status: serp_status)
    else
      all
    end
  end

  # 閲覧ロールとtel_filterに基づいた電話番号の絞り込み
  def self.apply_tel_role_filter(is_admin: false, is_worker: false, tel_filter: nil)
    if is_admin && tel_filter == "with_tel"
      where.not(tel: [nil, '', ' '])
    elsif is_admin && tel_filter == "without_tel"
      where(tel: [nil, '', ' '])
    elsif is_worker
      where(tel: [nil, '', ' '])
    else
      all
    end
  end

  # データ充足条件による絞り込み
  def self.apply_fill_filter(fill_filter)
    case fill_filter
    when "missing_tel"
      where("tel IS NULL OR TRIM(tel) = ''")
    when "missing_address"
      where("address IS NULL OR TRIM(address) = ''")
    when "missing_url"
      where("url IS NULL OR TRIM(url) = ''")
    when "missing_contact_url"
      where("contact_url IS NULL OR TRIM(contact_url) = ''")
    when "fully_enriched"
      where.not(tel: [nil, '', ' '])
           .where.not(address: [nil, '', ' '])
           .where.not(url: [nil, '', ' '])
           .where.not(contact_url: [nil, '', ' '])
    when "done_missing_tel"
      where(serp_status: "serp_done").where("tel IS NULL OR TRIM(tel) = ''")
    when "done_missing_address"
      where(serp_status: "serp_done").where("address IS NULL OR TRIM(address) = ''")
    else
      all
    end
  end

  # 最終更新日時フィルタ
  def self.apply_updated_at_filter(from_param, to_param, today_only_param)
    updated_from = Date.parse(from_param) rescue nil if from_param.present?
    updated_to   = Date.parse(to_param)   rescue nil if to_param.present?

    if updated_from || updated_to
      if updated_from && updated_to
        where(updated_at: updated_from.beginning_of_day..updated_to.end_of_day)
      elsif updated_from
        where("updated_at >= ?", updated_from.beginning_of_day)
      else
        where("updated_at <= ?", updated_to.end_of_day)
      end
    elsif today_only_param == "1"
      where(updated_at: Time.current.beginning_of_day..Time.current.end_of_day)
    else
      all
    end
  end

  # 作成日時の期間フィルタ
  def self.apply_created_at_range(range_start, range_end)
    if range_start && range_end
      where(created_at: range_start..range_end)
    elsif range_start
      where('created_at >= ?', range_start)
    elsif range_end
      where('created_at <= ?', range_end)
    else
      all
    end
  end

  # SERP情報補補完対象件数の計算
  def self.calculate_serp_target_count(base_scope)
    base_scope.where(serp_status: [nil, ''])
              .where(
                "(tel IS NULL OR TRIM(tel) = '') OR " \
                "(url IS NULL OR TRIM(url) = '') OR " \
                "(contact_url IS NULL OR TRIM(contact_url) = '')"
              ).count
  end

  # ダッシュボードサマリー統計の計算
  def self.calculate_dashboard_stats(base_scope)
    total = base_scope.count
    status_counts = base_scope.group(:serp_status).count

    {
      total: total,
      status: {
        null:     status_counts[nil].to_i + status_counts[""].to_i,
        queued:   status_counts["serp_queued"].to_i,
        done:     status_counts["serp_done"].to_i,
        imported: status_counts["serp_imported"].to_i,
        error:    status_counts["serp_error"].to_i
      },
      fill: {
        tel:         base_scope.where.not(tel: [nil, '', ' ']).count,
        address:     base_scope.where.not(address: [nil, '', ' ']).count,
        url:         base_scope.where.not(url: [nil, '', ' ']).count,
        contact_url: base_scope.where.not(contact_url: [nil, '', ' ']).count,
        full:        base_scope.where.not(tel: [nil, '', ' '])
                               .where.not(address: [nil, '', ' '])
                               .where.not(url: [nil, '', ' '])
                               .where.not(contact_url: [nil, '', ' '])
                               .count
      }
    }
  end
end
