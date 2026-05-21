module CustomersHelper
  ADDRESS_MUNICIPALITY_PATTERN = /市|区|町|村|郡/.freeze
  ADDRESS_DETAIL_PATTERN = /[0-9０-９]|丁目|番地|番|号|[-－ー]/.freeze
  ADDRESS_ACCESS_PATTERN = /駅(?:\s|$|車|徒歩|バス|から|より|[0-9０-９]+分)|徒歩|車\s*[0-9０-９]+分|バス\s*[0-9０-９]+分|バス停|バス利用|バスで|バス約|分圏内|アクセス|最寄り/.freeze
  DISPLAY_TIME_ZONE = "Tokyo".freeze

  SERP_STATUS_LABELS = {
    nil           => "未処理",
    ""            => "未処理",
    "serp_queued" => "処理中",
    "serp_done"   => "完了",
    "serp_imported" => "登録済み",
    "serp_error" => "エラー"
  }.freeze

  def serp_status_label(value)
    SERP_STATUS_LABELS[value] || value.to_s
  end

  def serp_run_result_label(value)
    case value.to_s
    when "", "pending"   then "待機中"
    when "updated"       then "更新あり"
    when "url_only"      then "URLのみ"
    when "no_candidate"  then "候補なし"
    when "excluded"      then "除外URLのみ"
    when "no_update"     then "更新なし"
    when "error"         then "エラー"
    else value.to_s
    end
  end

  def serp_status_badge_class(value)
    case value
    when nil, ""        then "ai-badge-gray"
    when "serp_queued"  then "ai-badge-yellow"
    when "serp_done"    then "ai-badge-green"
    when "serp_imported" then "ai-badge-blue"
    when "serp_error" then "ai-badge-red"
    else "ai-badge-gray"
    end
  end

  def serp_status_sc_badge_class(value)
    case value
    when nil, ""         then "sc-detect__badge--info"
    when "serp_queued"   then "sc-detect__badge--warning"
    when "serp_done"     then "sc-detect__badge--success"
    when "serp_imported" then "sc-detect__badge--info"
    when "serp_error"    then "sc-detect__badge--danger"
    else "sc-detect__badge--info"
    end
  end

  def fill_icon(value)
    if value.to_s.strip.present?
      content_tag(:span, "○", class: "ai-fill-ok", title: "取得済み")
    else
      content_tag(:span, "×", class: "ai-fill-ng", title: "未取得")
    end
  end

  def tel_quality_icon(customer)
    if customer&.tel.to_s.strip.present?
      content_tag(:span, "○", class: "ai-fill-ok", title: "公式または公式サイト由来の電話番号取得済み")
    elsif external_tel_evidence?(customer)
      content_tag(:span, "△", class: "ai-fill-warn", title: "外部サイト上に電話番号情報あり（公式未確認）")
    else
      content_tag(:span, "×", class: "ai-fill-ng", title: "電話番号未取得")
    end
  end

  def url_quality_icon(url)
    normalized = url.to_s.strip

    if normalized.blank?
      content_tag(:span, "×", class: "ai-fill-ng", title: "公式URL未取得")
    elsif official_url?(normalized)
      content_tag(:span, "○", class: "ai-fill-ok", title: "公式URL取得済み")
    else
      content_tag(:span, "△", class: "ai-fill-warn", title: "求人/企業DB等のため公式URL扱いしない")
    end
  end

  def official_url?(url)
    BrightData::UrlPolicy.official_url?(url)
  end

  def display_company_name(customer)
    raw = customer&.company.to_s.strip
    return "名称未設定" if raw.blank?

    normalized = BrightData::UrlPolicy.normalize_company_name(raw)
    return normalized if normalized.present? && noisy_company_display_name?(raw, normalized)

    raw
  end

  def detailed_address?(address)
    normalized = address.to_s.strip
    return false if normalized.blank?
    return false if normalized.match?(ADDRESS_ACCESS_PATTERN)
    return false if BrightData::Pipeline.send(:address_score, normalized).zero?

    normalized.match?(CustomersController::SERP_PREF_PATTERN) &&
      normalized.match?(ADDRESS_MUNICIPALITY_PATTERN) &&
      normalized.match?(ADDRESS_DETAIL_PATTERN)
  end

  def display_address(address)
    normalized = address.to_s.strip
    return nil unless detailed_address?(normalized)

    normalized
  end

  def address_quality_icon(address)
    normalized = address.to_s.strip

    if normalized.blank?
      content_tag(:span, "×", class: "ai-fill-ng", title: "住所未取得")
    elsif detailed_address?(normalized)
      content_tag(:span, "○", class: "ai-fill-ok", title: "番地相当まで取得済み")
    else
      content_tag(:span, "△", class: "ai-fill-warn", title: "都道府県・市区町村止まり、または駅/アクセス表記の可能性")
    end
  end

  def display_datetime(datetime)
    datetime&.in_time_zone(DISPLAY_TIME_ZONE)&.strftime("%m/%d %H:%M")
  end

  def percentage_of(part, total)
    return 0.0 if total.to_i.zero?
    (part.to_f / total * 100).round(1)
  end

  private

  def external_tel_evidence?(customer)
    return false if customer.blank?

    evidence_url = customer.contact_url.to_s.strip.presence || customer.url.to_s.strip.presence
    evidence_url.present? && BrightData::UrlPolicy.excluded_url?(evidence_url)
  end

  def noisy_company_display_name?(raw, normalized)
    raw != normalized &&
      raw.match?(/宅配課|配送課|配達課|営業課|総務課|事務課|管理課|採用課|人事課|物流課|運送課|法人番号|転職|求人|採用|評判|口コミ|[\/／].*(?:課|部|係|センター)/)
  end
end
