require 'net/http'
require 'nokogiri'

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

  # Column一覧ページ
  add "/columns", changefreq: 'daily', priority: 0.6

  # ---- Column詳細ページをdrafity.pro経由(ri-plus.jp/columns)からスクレイピングして収集 ----
  column_codes = []
  page = 1

  loop do
    uri = URI("https://ri-plus.jp/columns?page=#{page}")
    res = Net::HTTP.get_response(uri)
    break unless res.is_a?(Net::HTTPSuccess)

    doc = Nokogiri::HTML(res.body)
    links = doc.css('a[href^="/columns/"]').map { |a| a['href'] }
                .reject { |href| href == '/columns' }
                .map { |href| href.sub('/columns/', '') }

    break if links.empty?

    column_codes.concat(links)
    page += 1
    break if page > 100 # 安全装置(無限ループ防止)
  end

  column_codes.uniq.each do |code|
    add "/columns/#{code}",
        changefreq: 'weekly',
        priority: 0.5
  end
end