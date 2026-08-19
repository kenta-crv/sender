module ApplicationHelper
  def default_meta_tags
    {
      site: "豊富な人材集客力で企業の人材不足を解消|『J Work』",
      description: "豊富な人材集客力で企業の人材不足を解消|『J Work』。軽貨物・警備・建設・清掃業等様々な業界で活躍しています。",
      canonical: request.original_url,  # 優先されるurl
      charset: "UTF-8",
      reverse: true,
      separator: '|',
      icon: [
        { href: image_url('favicon.ico') },
        { href: image_url('favicon.ico'),  rel: 'apple-touch-icon' },
      ],

    }
  end

  def plan_priority_wait_notice
    PlanPriorityQueue.wait_notice_for(
      client: current_client,
      admin: acting_as_admin?
    )
  end

  def organization_json_ld
    {
      "@context" => "https://schema.org",
      "@type" => "Organization",
      "name" => "Okurite",
      "legalName" => "株式会社J Work",
      "url" => "https://okurite.pro/",
      "logo" => "https://okurite.pro#{image_path('favicon.ico')}",
      "description" => "AIを活用した低価格かつ大量アプローチを叶えるトータル営業代行サービス。",
      "address" => {
        "@type" => "PostalAddress",
        "streetAddress" => "浜松町２丁目２番１５号２Ｆ",
        "addressLocality" => "港区",
        "addressRegion" => "東京都",
        "addressCountry" => "JP"
      }
    }.to_json
  end

  def website_json_ld
    {
      "@context" => "https://schema.org",
      "@type" => "WebSite",
      "name" => "Okurite",
      "url" => "https://okurite.pro/",
      "inLanguage" => "ja",
      "publisher" => {
        "@type" => "Organization",
        "name" => "株式会社J Work"
      }
    }.to_json
  end

  def faq_page_json_ld(items)
    entities = Array(items).filter_map do |item|
      q = (item.is_a?(Array) ? item[0] : (item[:q] || item["q"])).to_s.strip
      a = (item.is_a?(Array) ? item[1] : (item[:a] || item["a"])).to_s.strip
      next if q.blank? || a.blank?

      {
        "@type" => "Question",
        "name" => q,
        "acceptedAnswer" => {
          "@type" => "Answer",
          "text" => a
        }
      }
    end
    return if entities.blank?

    {
      "@context" => "https://schema.org",
      "@type" => "FAQPage",
      "mainEntity" => entities
    }.to_json
  end

  def lp_faqs_for_current_page
    respond_to?(:lp_faq_items_for_page) ? lp_faq_items_for_page : []
  end

  def customer_delivery_status(customer, client_id: nil, admin_id: nil)
    client_id ||= current_client&.id if client_signed_in?
    admin_id ||= current_admin&.id if acting_as_admin?

    if client_id.present? && customer.opted_out_for?(client_id)
      { label: "このクライアントから配信停止済み", css: "delivery-status-badge--client-opt-out" }
    elsif admin_id.present? && customer.delivery_opt_outs.exists?(admin_id: admin_id)
      { label: "この管理者から配信停止済み", css: "delivery-status-badge--client-opt-out" }
    else
      { label: "送信可能", css: "delivery-status-badge--ok" }
    end
  end

    def customer_opted_out_client_labels(customer)
    customer.delivery_opt_outs.includes(:client).map do |opt_out|
      if opt_out.client_id.present?
        opt_out.client&.company.presence || opt_out.client&.email || "Client ##{opt_out.client_id}"
      elsif opt_out.admin_id.present?
        "Admin ##{opt_out.admin_id}"
      end
    end
    .compact
  end

  def show_plan_upgrade_banner?
    return false unless client_signed_in?
    return false if acting_as_admin?
    return false if %w[plans checkout].include?(controller_name)

    controller_path.start_with?("dashboard") || %w[customers submissions form_submissions draft_customers].include?(controller_name)
  end

end
