class Customer < ApplicationRecord
  has_many :calls, dependent: :destroy  
  has_one :last_call, -> { order(created_at: :desc) }, class_name: 'Call'
  has_one :last_form_call, -> { where(call_type: 'form').order(created_at: :desc) }, class_name: 'Call'
  belongs_to :worker, optional: true
  belongs_to :client, optional: true
  before_create :generate_unsubscribe_token

  # ダッシュ系を含む「実質空値」のSQL断片を生成するユーティリティ
  # 例: blank_sql("tel") => "(tel IS NULL OR TRIM(tel) IN ('', '-', '－', '−', 'ー') OR tel = ' ')"
  DASH_VARIANTS = ["'-'", "'－'", "'−'", "'ー'", "'–'"].freeze

  def self.blank_sql(col)
    dash_list = DASH_VARIANTS.join(", ")
    "(#{col} IS NULL OR TRIM(#{col}) = '' OR #{col} = ' ' OR #{col} = ' ' OR TRIM(#{col}) IN (#{dash_list}))"
  end

  scope :between_created_at, ->(from, to) {
    where(created_at: from..to).where.not(tel: nil)
  }

  scope :between_called_at, ->(from, to) {
    where(created_at: from..to)
  }

  scope :ltec_calls_count, ->(count) {
    filter_ids = joins(:calls).group("calls.customer_id").having('count(*) <= ?', count).count.keys
    where(id: filter_ids)
  }

  # プレビュー（draft画面）と実行（execute_from_db）で同じ条件を使うための共通スコープ。
  scope :serp_extraction_targets, ->(fill_filter = nil) {
    base = where(serp_status: [nil, ''])

    if fill_filter.present?
      # 画面で充足フィルタが選択されている場合は、その条件に限定する
      base.apply_fill_filter(fill_filter)
    else
      # ★ AND から OR に修正：tel または url のどちらかが「実質空値」の企業を抽出
      base.where(
        "#{blank_sql('tel')} OR #{blank_sql('url')}"
      )
    end
  }

  def self.ransackable_associations(auth_object = nil)
    %w[calls last_call]
  end

  def self.ransackable_attributes(auth_object = nil)
    %w[
      company
      tel
      address
      email
      url
      business
      genre
      contact_url
      fobbiden
      created_at
      updated_at
      id
    ]
  end

  def generate_unsubscribe_token
    self.unsubscribe_token ||= SecureRandom.hex(32)
  end

  def self.draft_base_scope(current_client_id: nil, is_admin: false, industry_name: nil)
    scope = where(serp_status: [nil, '', 'serp_queued', 'serp_done', 'serp_imported', 'serp_error'])

    if is_admin
      # 管理者は全件
    elsif current_client_id.present?
      scope = scope.where(client_id: current_client_id)
    else
      scope = scope.none
    end

    scope = scope.where(business: industry_name) if industry_name.present?
    scope
  end

  def self.apply_status_filter(status)
    status.present? ? where(status: status) : all
  end

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

  def self.apply_fill_filter(fill_filter)
    case fill_filter
    when "missing_tel"
      where(blank_sql("tel"))
    when "missing_address"
      where(blank_sql("address"))
    when "partial_address"
      # address自体は存在するが不十分（スコアが0）な行。Ruby側フィルタ不可のためSQLで近似。
      # ダッシュ系も含めて「空またはダッシュ」は missing_address 扱いにし、
      # partial_address は「何か入っているが都道府県+市区町村+番地が揃っていない」行を指す。
      where.not(blank_sql("address")).where(
        "address NOT REGEXP '^(#{prefecture_regexp_fragment})'" \
        " OR address NOT REGEXP '(市|区|町|村|郡)'" \
        " OR address NOT REGEXP '[0-9０-９]|丁目|番地|番|号'"
      )
    when "missing_url"
      where(blank_sql("url"))
    when "missing_contact_url"
      where(blank_sql("contact_url"))
    when "fully_enriched"
      where("NOT #{blank_sql('tel')}")
        .where("NOT #{blank_sql('address')}")
        .where("NOT #{blank_sql('url')}")
        .where("NOT #{blank_sql('contact_url')}")
    when "done_missing_tel"
      where(serp_status: "serp_done").where(blank_sql("tel"))
    when "done_missing_address"
      where(serp_status: "serp_done").where(blank_sql("address"))
    when "done_partial_address"
      where(serp_status: "serp_done")
        .where.not(blank_sql("address"))
        .where(
          "address NOT REGEXP '^(#{prefecture_regexp_fragment})'" \
          " OR address NOT REGEXP '(市|区|町|村|郡)'" \
          " OR address NOT REGEXP '[0-9０-９]|丁目|番地|番|号'"
        )
    else
      all
    end
  end

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

  def self.calculate_serp_target_count(base_scope, fill_filter = nil)
    base_scope.serp_extraction_targets(fill_filter).count
  end

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
        tel:         base_scope.where("NOT #{blank_sql('tel')}").count,
        address:     base_scope.where("NOT #{blank_sql('address')}").count,
        url:         base_scope.where("NOT #{blank_sql('url')}").count,
        contact_url: base_scope.where("NOT #{blank_sql('contact_url')}").count,
        full:        base_scope
                       .where("NOT #{blank_sql('tel')}")
                       .where("NOT #{blank_sql('address')}")
                       .where("NOT #{blank_sql('url')}")
                       .where("NOT #{blank_sql('contact_url')}")
                       .count
      }
    }
  end

  private

  # apply_fill_filter の partial_address 用。DB が MySQL/MariaDB 前備。
  # SQLite3 では REGEXP が使えないため、必要に応じてアダプタ分岐を追加すること。
  def self.prefecture_regexp_fragment
    '東京都|北海道|(?:大阪|京都)府|.+県'
  end
end