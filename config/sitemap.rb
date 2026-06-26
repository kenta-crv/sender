# 1. 実行時にモデルなどの定数が未定義（NameError）になるのを防ぐため、
#    Railsアプリケーションの環境を明示的に読み込みます。
Rails.application.eager_load! if defined?(Rails)

SitemapGenerator::Sitemap.default_host = "https://ri-plus.jp"

SitemapGenerator::Sitemap.create do
  # トップページ
  add root_path, changefreq: 'hourly', priority: 1.0

  # 各ジャンルLP
  tops = %w[
    okurite
    sales
  ]

  tops.each do |top|
    add "/#{top}", changefreq: 'monthly', priority: 0.7
  end

  # Column（LP配下）
  # 念のため定義されているかチェック（安全策）
  if defined?(Column)
    Column.find_each do |column|
      next unless column.code.present?   # code があるものだけ追加
      
      add "columns?column=#{column.code}",
          lastmod: column.updated_at,
          changefreq: 'weekly',
          priority: 0.5
    end
  end
end