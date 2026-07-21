module TopsHelper
  # LP / トップから内部リンクする代表記事（Draftiy app ジャンル）
  FEATURED_COLUMNS = {
    top: [
      { title: "営業フレームワークを活用した顧客関係管理", path: "/columns/customer-relationship-management-sales-framework" },
      { title: "営業成果を測定するためのKPI設定ガイド", path: "/columns/kpi-setting-guide-for-sales-results" },
      { title: "BtoB営業改善のためのPDCAサイクルの実践ガイド", path: "/columns/btob-eigyou-kaizen-pdca-fb994e66-4617-4210-8561-ec6f07ba0dfa" },
      { title: "受注率を高めるための営業トレーニングプログラム", path: "/columns/sales-training-program" },
      { title: "営業ファネル分析を行う際のデータ収集方法", path: "/columns/eigyou-faneru-bunseki-data-shuushuu" }
    ],
    okurite: [
      { title: "営業フレームワークを活用した顧客関係管理", path: "/columns/customer-relationship-management-sales-framework" },
      { title: "営業成果を測定するためのKPI設定ガイド", path: "/columns/kpi-setting-guide-for-sales-results" },
      { title: "BtoB営業改善のためのPDCAサイクルの実践ガイド", path: "/columns/btob-eigyou-kaizen-pdca-fb994e66-4617-4210-8561-ec6f07ba0dfa" },
      { title: "営業ファネル分析を行う際のデータ収集方法", path: "/columns/eigyou-faneru-bunseki-data-shuushuu" },
      { title: "営業マネジメントにおけるデータ活用の重要性", path: "/columns/importance-of-data-utilization-in-sales-management" }
    ],
    sales: [
      { title: "営業マネジメントフレームワークの導入ステップ", path: "/columns/sales-management-framework-implementation-steps" },
      { title: "営業成果を測定するためのKPI設定ガイド", path: "/columns/kpi-setting-guide-for-sales-results" },
      { title: "受注率を高めるための営業トレーニングプログラム", path: "/columns/sales-training-program" },
      { title: "リモート営業におけるマネジメント手法", path: "/columns/remote-sales-management-techniques" },
      { title: "営業マネジメントにおけるリーダーシップの役割", path: "/columns/leadership-in-sales-management" }
    ]
  }.freeze

  def featured_columns_for(page_key)
    FEATURED_COLUMNS[page_key.to_sym] || FEATURED_COLUMNS[:top]
  end
end
