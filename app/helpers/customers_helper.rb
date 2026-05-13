module CustomersHelper
  ADDRESS_MUNICIPALITY_PATTERN = /市|区|町|村|郡/.freeze
  ADDRESS_DETAIL_PATTERN = /[0-9０-９]|丁目|番地|番|号|[-－ー]/.freeze

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

  def fill_icon(value)
    if value.to_s.strip.present?
      content_tag(:span, "○", class: "ai-fill-ok", title: "取得済み")
    else
      content_tag(:span, "×", class: "ai-fill-ng", title: "未取得")
    end
  end

  def detailed_address?(address)
    normalized = address.to_s.strip
    return false if normalized.blank?

    normalized.match?(CustomersController::SERP_PREF_PATTERN) &&
      normalized.match?(ADDRESS_MUNICIPALITY_PATTERN) &&
      normalized.match?(ADDRESS_DETAIL_PATTERN)
  end

  def address_quality_icon(address)
    normalized = address.to_s.strip

    if normalized.blank?
      content_tag(:span, "×", class: "ai-fill-ng", title: "住所未取得")
    elsif detailed_address?(normalized)
      content_tag(:span, "○", class: "ai-fill-ok", title: "番地相当まで取得済み")
    else
      content_tag(:span, "△", class: "ai-fill-warn", title: "都道府県・市区町村止まりの可能性")
    end
  end

  def percentage_of(part, total)
    return 0.0 if total.to_i.zero?
    (part.to_f / total * 100).round(1)
  end
end
