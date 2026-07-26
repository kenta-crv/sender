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
    case action_name
    when "okurite"
      [
        ["AI問い合わせフォーム送信代行の仕組みを教えてください。", "『Okurite』は、企業が指定するリストに対して、最適な問い合わせフォームをAIが自動判別して営業文を届けるサービスです。AIが入力項目を理解し、人間が送るような自然な形でアプローチを自動化します。"],
        ["送信先のリストはどのように作成しますか？", "業種、地域、企業規模だけでなく、特定のキーワードや直近の求人情報などから「今ニーズがある企業」を常に抽出しております。もちろん御社自身で保持しているリストに送信する事も可能です。"],
        ["リストはありますが、問い合わせフォームURLがありません。", "問い合わせフォームが把握できない場合、当社のAIシステムが企業トップページURLからスクリーニングし、問い合わせフォームを自動で検出します。"],
        ["1日に送信できる上限はありますか？", "企業のドメイン保護や受信側のマナーを考慮し、一定の時間間隔を空けながら送信作業を行います。そのため無限に送信出来るものとは異なります。"]
      ]
    when "sales"
      [
        ["AI営業代行での商談提供の定義を教えてください。", "『Okurite』では、AIアプローチに対して顧客が主体的に問い合わせや返信を行い、商談の合意が取れた状態を「有効商談」と基本定義しています。しかし、成功報酬会社ではないため、具体的な商談定義は、取引企業様毎に決定しております。"],
        ["毎月の報告はありますか？", "はい。毎月の実績報告および、Webミーティングで毎月状況報告とPDCA設計を行います。"],
        ["自動フォーム営業ができない業種はありますか？", "基本的にはBtoB全般で利用可能ですが、問い合わせフォームの形式が通常と異なる場合は、AI対策をしている先にアプローチすることはできません。全件送信を実現したい場合、手動送信が可能なエンタープライズを導入してください。"],
        ["成約時の成果報酬は発生しますか？", "当社のパッケージは「有効商談の提供」までのサポートとなっており、成約時の成果報酬はいただいておりません。月額の範囲内で獲得した商談からの売上はすべて御社の利益となります。"],
        ["『Okurite』で結果が出やすい商材は？", "SaaS、人材サービス、広告、コンサルティングなど、BtoB向けのサービス全般で高い効果を発揮します。定期的に同一企業へのアプローチも可能なので、取りこぼしを最小限にアプローチできます。"]
      ]
    else
      []
    end
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
