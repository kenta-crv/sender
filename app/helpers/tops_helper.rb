module TopsHelper
  # LP / トップから内部リンクする代表記事（Draftiy app ジャンル）
  FEATURED_COLUMNS = {
    top: [
      { title: "フォーム営業とは何か？営業プロセス全体像の解説", path: "/columns/app-complete-guide" },
      { title: "問い合わせフォーム営業は有効か？送信率100%を実現する運用設計と注意点", path: "/columns/inquiry-form-sales-effectiveness" },
      { title: "営業代行を利用する際の注意点と失敗しないためのポイント", path: "/columns/sales-outsourcing-failure-cases-app" },
      { title: "【AI営業リスト生成】AI・プログラミング・人のシナジーを活かしたリスト制作の最大化", path: "/columns/ai-sales-list-generation" },
      { title: "問い合わせ営業の進め方｜リスト作成から商談化までの流れ", path: "/columns/inquiry-sales-process" }
    ],
    okurite: [
      { title: "フォーム営業とは何か？営業プロセス全体像の解説", path: "/columns/app-complete-guide" },
      { title: "問い合わせフォーム営業は有効か？送信率100%を実現する運用設計と注意点", path: "/columns/inquiry-form-sales-effectiveness" },
      { title: "フォーム営業の自動化とは？仕組みと導入ステップを解説", path: "/columns/form-sales-automation" },
      { title: "問い合わせフォーム営業を自動化するメリット・デメリット", path: "/columns/contact-form-sales-automation" },
      { title: "人力営業と問い合わせフォーム営業自動化の違い｜コストと成果を比較", path: "/columns/human-sales-vs-automation" }
    ],
    sales: [
      { title: "営業代行を利用する際の注意点と失敗しないためのポイント", path: "/columns/sales-outsourcing-failure-cases-app" },
      { title: "営業代行で失敗しない！BtoB企業が知っておくべき業界構造と主要プレイヤー", path: "/columns/btob-sales-agency" },
      { title: "テレアポ型営業代行を導入すべきか？ BtoB企業の新規商談獲得における実務的判断基準", path: "/columns/btob-sales-outsourcing-telemarketing-meeting-app" },
      { title: "営業代行業者選びの失敗を避けるためのチェックリスト", path: "/columns/eigyou-daiyou-gyousha-sentaku-checklist" },
      { title: "【完全版】アウトバウンド営業の教科書：最新AI×プロの技術で商談を最大化する方法", path: "/columns/outbound-sales-guide" }
    ]
  }.freeze

  OKURITE_FAQ_CATEGORIES = [
    ["service", "サービスについて", "comments"],
    ["list", "リスト・送信", "list"],
    ["pricing", "料金・トライアル", "yen"],
    ["setup", "申し込み・開始", "rocket"]
  ].freeze

  OKURITE_FAQ_ITEMS = [
    # service
    { category: "service", q: "Okuriteは何をするサービスですか？", a: "指定リストに対し、AIが問い合わせフォームを判別・入力し、営業文を自動送信するBtoB向けフォーム営業ツールです。文面は自由に設定でき、反応のあった案件を人の営業がフォローする使い方が一般的です。" },
    { category: "service", q: "フォーム送信だけのプランと営業代行の違いは？", a: "本ページのOkuriteはフォーム送信の自動化に特化しています。商談獲得まで含む伴走パッケージはセールスページでご案内しています。" },
    { category: "service", q: "送信は迷惑行為になりませんか？", a: "ドメイン保護と受信側マナーを考慮し、送信間隔と月間上限を設けた運用です。無限送信や過度な一斉送信は行いません。" },
    { category: "service", q: "送信結果はどこで見られますか？", a: "管理画面で送信状況・成功／失敗・返信などの進捗を確認できます。" },

    # list
    { category: "list", q: "リストがなくても使えますか？", a: "はい。業種・地域・企業規模やキーワード、求人情報などからニーズのある企業を抽出できます。自社リストのみで送信することも可能です。" },
    { category: "list", q: "問い合わせフォームURLがなくても送れますか？", a: "はい。企業トップページURLからAIが問い合わせフォームを自動検出します。検出できなかった先は送信対象から除外されます。エンタープライズでは手動送信などもご相談可能です。" },
    { category: "list", q: "月間の送信・検出上限は？", a: "トライアル：送信#{Subscription::PLAN_DELIVERY_LIMITS[:trial]}件・フォーム検出#{Subscription::PLAN_FORM_DETECTION_LIMITS[:trial]}件・AIリスト#{Subscription::PLAN_SERP_API_LIMITS[:trial]}件。スタンダード：送信#{Subscription::PLAN_DELIVERY_LIMITS[:standard].to_s(:delimited)}件・検出#{Subscription::PLAN_FORM_DETECTION_LIMITS[:standard].to_s(:delimited)}件・リスト#{Subscription::PLAN_SERP_API_LIMITS[:standard].to_s(:delimited)}件。エンタープライズ：送信#{Subscription::PLAN_DELIVERY_LIMITS[:enterprise].to_s(:delimited)}件・検出#{Subscription::PLAN_FORM_DETECTION_LIMITS[:enterprise].to_s(:delimited)}件・リスト#{Subscription::PLAN_SERP_API_LIMITS[:enterprise].to_s(:delimited)}件です。" },
    { category: "list", q: "同一企業への再アプローチはできますか？", a: "はい。運用ルールに沿って間隔を空けた再アプローチが可能です。" },

    # pricing
    { category: "pricing", q: "無料トライアルの条件は？", a: "#{Subscription::TRIAL_DAYS}日間・0円です。アカウント登録だけで開始でき、クレジットカードは不要です。上限は送信#{Subscription::PLAN_DELIVERY_LIMITS[:trial]}件・フォーム検出#{Subscription::PLAN_FORM_DETECTION_LIMITS[:trial]}件・AIリスト制作#{Subscription::PLAN_SERP_API_LIMITS[:trial]}件です。" },
    { category: "pricing", q: "有料プランの料金は？", a: "スタンダード通常月額#{Subscription::PLAN_PRICES[:standard].to_s(:delimited)}円（送信・検出各#{Subscription::PLAN_DELIVERY_LIMITS[:standard].to_s(:delimited)}件）。初回#{Subscription::STANDARD_INTRO_MONTHS}ヶ月は#{Subscription::STANDARD_INTRO_PERCENT_OFF}%OFFで#{Subscription.standard_intro_price.to_s(:delimited)}円/月。エンタープライズ月額#{Subscription::PLAN_PRICES[:enterprise].to_s(:delimited)}円（送信#{Subscription::PLAN_DELIVERY_LIMITS[:enterprise].to_s(:delimited)}件）。初期費用は0円で、いつでも解約できます。詳細は料金セクションをご確認ください。" },
    { category: "pricing", q: "トライアル終了後はどうなりますか？", a: "終了後は自動課金されません。継続する場合は、ログイン後の料金プラン画面からスタンダード（推奨・初回3ヶ月15%OFF）またはエンタープライズにお申し込みください。不要なら、そのまま終了します。" },
    { category: "pricing", q: "成果報酬はかかりますか？", a: "かかりません。月額プランの範囲でのご利用です。成約時の成果報酬もいただきません。" },
    { category: "pricing", q: "請求書払いはできますか？", a: "法人利用の場合、契約形態に応じてご案内します。ご希望はお問い合わせください。" },

    # setup
    { category: "setup", q: "申し込みから初回送信までの手順は？", a: "①「トライアルを実施」などからアカウント登録（会社名・氏名・連絡先など・約30秒）→②登録完了と同時にトライアル開始（カード不要）→③ダッシュボードでリスト準備・文面設定→④フォーム検出／送信開始、の順です。" },
    { category: "setup", q: "有料プランへの切り替え方は？", a: "ログイン後の料金プラン画面からスタンダードまたはエンタープライズを選び、クレジットカードでお申し込みください。" },
    { category: "setup", q: "文面は自由に設定できますか？", a: "はい。商材やターゲットに合わせて送信文面を設定・調整できます。導入時の文面・ターゲット設計の相談も可能です。" }
  ].freeze

  SALES_FAQ_CATEGORIES = [
    ["service", "サービスについて", "comments"],
    ["pricing", "料金・成果", "yen"],
    ["setup", "申し込み・運用", "rocket"],
    ["results", "商談・成果", "chart"]
  ].freeze

  SALES_FAQ_ITEMS = [
    # service
    { category: "service", q: "有効商談とは何ですか？", a: "AIアプローチに対し、相手が主体的に問い合わせ・返信し、商談の合意が取れた状態を基本定義としています。成功報酬型ではないため、具体的な定義は取引先ごとにすり合わせます。" },
    { category: "service", q: "フォーム送信だけのOkuriteとの違いは？", a: "セールスパッケージは商談獲得までの伴走（リスト・送信・フォロー設計・定例など）を含みます。送信自動化のみならOkurite本体ページをご覧ください。" },
    { category: "service", q: "どんな商材・業種向きですか？", a: "SaaS、人材、広告、コンサルなどBtoB全般向きです。フォーム形式が特殊・AI対策されている先には自動送信できない場合があり、その場合はエンタープライズの手動送信をご検討ください。" },
    { category: "service", q: "成約時の成果報酬はありますか？", a: "ありません。有効商談の提供までが範囲で、成約後の売上はすべて御社の利益です。" },

    # pricing
    { category: "pricing", q: "パッケージ料金はいくらですか？", a: "ライト：初期0円・月額49,800円。スタンダード：初期50,000円・月額198,000円（テレアポ1,000call・定例あり）。エンタープライズ：初期50,000円・月額298,000円（テレアポ2,000call・送信制限なし）。詳細は料金セクションをご確認ください。" },
    { category: "pricing", q: "ライトと上位プランの違いは？", a: "ライトは検出・送信各15,000件中心でリスト制作・架電・定例MTGは含みません。スタンダード以上はリスト制作・AI架電・テレアポ・定例報告が入り、エンタープライズは検出・送信の制限なしです。" },
    { category: "pricing", q: "請求書払いや契約期間は？", a: "法人契約ではお支払い方法を相談のうえご案内します。契約条件はパッケージごとに異なり、見積時に明示します。" },

    # setup
    { category: "setup", q: "申し込みの流れは？", a: "①料金セクションまたは資料請求・お問い合わせから連絡→②商材・ターゲット・目標件数のヒアリング→③パッケージ選定・見積→④契約後、文面・ターゲット設定→⑤送信・フォロー運用開始、の順です。ライトはトライアル導線からも開始できます。" },
    { category: "setup", q: "導入時に必要な準備は？", a: "商材情報、ターゲット条件、訴求方針です。リストがない場合もご相談可能です。窓口担当がいれば開始でき、日々の送信作業は仕組み側で進められます。" },
    { category: "setup", q: "毎月の報告はありますか？", a: "はい。実績報告とWebミーティングで状況共有・PDCA設計を行います（スタンダード以上の定例含む）。" },

    # results
    { category: "results", q: "どのくらいの商談数が期待できますか？", a: "商材・ターゲット・時期で変動します。過去実績や仮説をもとに目標設計を一緒に行います。" },
    { category: "results", q: "反応が弱い場合はどうしますか？", a: "文面・ターゲット・送信タイミングを見直し、毎月の報告で改善を続けます。" },
    { category: "results", q: "商談後の成約は誰が担当しますか？", a: "成約活動は御社の営業チームが担当します。パッケージ範囲は有効商談の提供までです。" }
  ].freeze

  def featured_columns_for(page_key)
    FEATURED_COLUMNS[page_key.to_sym] || FEATURED_COLUMNS[:top]
  end

  def okurite_faq_categories
    OKURITE_FAQ_CATEGORIES
  end

  def okurite_faq_items
    OKURITE_FAQ_ITEMS
  end

  def sales_faq_categories
    SALES_FAQ_CATEGORIES
  end

  def sales_faq_items
    SALES_FAQ_ITEMS
  end

  def lp_faq_categories_for_page
    case action_name
    when "okurite" then okurite_faq_categories
    when "sales" then sales_faq_categories
    else []
    end
  end

  def lp_faq_items_for_page
    case action_name
    when "okurite" then okurite_faq_items
    when "sales" then sales_faq_items
    else []
    end
  end
end
