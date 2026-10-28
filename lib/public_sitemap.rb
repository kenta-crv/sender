require "net/http"
require "nokogiri"
require "time"

# ブランドサイトの sitemap.xml を組み立てる。
# lastmod 未指定だと sitemap_generator が生成時刻を入れるため、nil は明示して省略する。
class PublicSitemap
  Response = Struct.new(:code, :body, keyword_init: true)

  def self.compose(host:, static_entries:, columns_index: "/columns", include_recruits: false, fetcher: nil)
    getter = fetcher || default_fetcher(host)
    entries = []

    static_entries.each do |entry|
      response = getter.call(entry[:path])
      next unless keep_without_check?(response)

      entries << entry.merge(lastmod: nil)
    end

    entries.concat(collect_columns(getter, columns_index)) if columns_index.present?
    entries.concat(collect_recruits(getter)) if include_recruits
    entries
  end

  def self.write!(host:, entries:, public_path: nil)
    SitemapGenerator::Sitemap.default_host = host
    SitemapGenerator::Sitemap.include_root = false
    SitemapGenerator::Sitemap.include_index = false
    SitemapGenerator::Sitemap.compress = false
    SitemapGenerator::Sitemap.sitemaps_path = ""
    SitemapGenerator::Sitemap.search_engines.clear
    SitemapGenerator::Sitemap.public_path = public_path if public_path

    SitemapGenerator::Sitemap.create(include_root: false) do
      entries.each do |entry|
        add entry[:path],
            changefreq: entry[:changefreq],
            priority: entry[:priority],
            lastmod: entry[:lastmod]
      end
    end
  end

  def self.collect_columns(fetcher, list_path)
    list_response = fetcher.call(list_path)
    paths = paginate_paths(fetcher, list_path) { |html| column_paths(html) }

    articles = paths.filter_map do |path|
      response = fetcher.call(path)
      next unless indexable?(response)

      {
        path: path,
        lastmod: modified_time(response.body),
        changefreq: "weekly",
        priority: 0.5
      }
    end

    entries = []
    if indexable?(list_response)
      entries << {
        path: list_path,
        lastmod: articles.filter_map { |entry| entry[:lastmod] }.max,
        changefreq: "daily",
        priority: 0.6
      }
    end
    entries + articles
  end

  def self.collect_recruits(fetcher)
    list_path = "/recruits"
    list_response = fetcher.call(list_path)
    paths = indexable?(list_response) ? recruit_paths(list_response.body) : []

    items = paths.filter_map do |path|
      response = fetcher.call(path)
      next unless indexable?(response)

      { path: path, lastmod: nil, changefreq: "weekly", priority: 0.5 }
    end

    entries = []
    if keep_without_check?(list_response) && (list_response.nil? || indexable?(list_response))
      entries << { path: list_path, lastmod: nil, changefreq: "daily", priority: 0.6 }
    end
    entries + items
  end

  def self.column_paths(html)
    paths_matching(html, 'a[href*="/columns/"]') do |href|
      next unless href.match?(%r{/columns/[^/]+/?\z})

      code = href.sub(%r{\A.*/columns/}, "").delete_suffix("/")
      code.present? ? "/columns/#{code}" : nil
    end
  end

  def self.recruit_paths(html)
    paths_matching(html, 'a[href*="/recruits/"]') do |href|
      id = href[%r{/recruits/(\d+)/?\z}, 1]
      id.present? ? "/recruits/#{id}" : nil
    end
  end

  def self.modified_time(html)
    document = Nokogiri::HTML(html.to_s)
    raw = document.at_css('meta[property="article:modified_time"]')&.[]("content")
    raw = raw.to_s.strip
    raw = document.at_css("[data-content-updated-at]")&.[]("data-content-updated-at") if raw.empty?
    parse_time(raw)
  end

  def self.indexable?(response)
    return false unless response
    return false unless response.code.to_i == 200

    !noindex?(response.body)
  end

  def self.noindex?(html)
    html.to_s.scan(/<meta\b[^>]*>/i).any? do |tag|
      robots = tag.match?(/\b(?:name|property)\s*=\s*["'](?:robots|googlebot)["']/i)
      robots && tag.match?(/\bnoindex\b/i)
    end
  end

  def self.keep_without_check?(response)
    return true if response.nil?

    indexable?(response)
  end

  def self.parse_time(value)
    text = value.to_s.strip
    return nil if text.empty?

    Time.zone.parse(text)
  rescue ArgumentError, TypeError
    nil
  end

  def self.default_fetcher(host)
    lambda do |path|
      http_get(host, path)
    end
  end

  def self.http_get(host, path)
    uri = URI.join("#{host.sub(%r{/+\z}, "")}/", path.sub(%r{\A/}, ""))
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = 10
    http.read_timeout = 20
    response = http.request(Net::HTTP::Get.new(uri))
    Response.new(code: response.code.to_i, body: response.body.to_s)
  rescue StandardError => e
    warn "[sitemap] #{host}#{path} の取得に失敗しました: #{e.class}: #{e.message}"
    nil
  end

  def self.paginate_paths(fetcher, list_path)
    paths = []
    page = 1
    loop do
      response = fetcher.call(page_path(list_path, page))
      break unless indexable?(response)

      found = yield(response.body)
      fresh = found - paths
      break if fresh.empty?

      paths.concat(fresh)
      page += 1
      break if page > 100
    end
    paths
  end

  def self.page_path(list_path, page)
    separator = list_path.include?("?") ? "&" : "?"
    "#{list_path}#{separator}page=#{page}"
  end

  def self.paths_matching(html, selector)
    document = Nokogiri::HTML(html.to_s)
    document.css(selector).filter_map do |anchor|
      href = anchor["href"].to_s.split("?").first
      yield(href)
    end.uniq
  end
  private_class_method :paginate_paths, :page_path, :paths_matching, :default_fetcher
end
