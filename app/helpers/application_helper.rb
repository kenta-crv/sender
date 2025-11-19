module ApplicationHelper
  def default_meta_tags
    {
      site: "軽貨物事業なら|『OK配送』",
      description: "軽貨物事業なら|『OK配送』",
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

end
