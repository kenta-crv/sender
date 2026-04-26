module CustomersHelper
  SERP_STATUS_LABELS = {
    nil           => "未処理",
    ""            => "未処理",
    "serp_queued" => "処理中",
    "serp_done"   => "完了",
    "serp_imported" => "登録済み"
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

  def percentage_of(part, total)
    return 0.0 if total.to_i.zero?
    (part.to_f / total * 100).round(1)
  end
end
