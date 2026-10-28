require Rails.root.join("lib/public_sitemap")

host = "https://okurite.pro"
entries = PublicSitemap.compose(
  host: host,
  static_entries: [
    { path: "/", changefreq: "hourly", priority: 1.0 },
    { path: "/okurite", changefreq: "monthly", priority: 0.7 },
    { path: "/sales", changefreq: "monthly", priority: 0.7 }
  ]
)

PublicSitemap.write!(host: host, entries: entries)
