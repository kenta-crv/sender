SitemapGenerator::Sitemap.default_host = "https://okey.work"

SitemapGenerator::Sitemap.create do
  # トップページ
  add root_path, changefreq: 'hourly', priority: 1.0

  # 各ジャンルLP
  lps = %w[
    cargo
    security
    construction
    cleaning
    event
    logistics
    recruit
    app
    ads
  ]

  lps.each do |lp|
    add "/#{lp}", changefreq: 'monthly', priority: 0.7
  end

  # Column（LP配下）
  Column.find_each do |column|
    lp = column.genre # 例: "cargo"

    add "/#{lp}/columns/#{column.id}",
        lastmod: column.updated_at,
        priority: 0.5
  end
end
