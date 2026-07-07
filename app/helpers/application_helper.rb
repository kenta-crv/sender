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
      admin: admin_signed_in?
    )
  end

  def customer_delivery_status(customer, client_id: nil)
    client_id ||= current_client&.id if client_signed_in?

    if customer.fobbiden.to_s.in?(%w[t true])
      { label: "全クライアント共通で送信禁止", css: "delivery-status-badge--global-ng" }
    elsif client_id.present? && customer.opted_out_for?(client_id)
      { label: "このクライアントから配信停止済み", css: "delivery-status-badge--client-opt-out" }
    else
      { label: "送信可能", css: "delivery-status-badge--ok" }
    end
  end

  def customer_opted_out_client_labels(customer)
    customer.delivery_opt_outs.includes(:client).map do |opt_out|
      opt_out.client&.company.presence || opt_out.client&.email || "Client ##{opt_out.client_id}"
    end
  end

end
