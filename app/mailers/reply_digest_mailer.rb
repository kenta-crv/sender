# 返信の仕分け結果を毎日通知する
class ReplyDigestMailer < ApplicationMailer
  TO = 'info@j-work.jp'.freeze

  def daily(counts, intents = {})
    @counts = counts
    @intents = intents
    @base_url = Rails.env.production? ? 'https://okurite.pro' : 'http://localhost:3000'
    headers['X-Okurite-Reply-Digest'] = '1'
    mail(
      to: TO,
      from: 'info@j-work.jp',
      subject: "【Okurite】返信の仕分け 人の返信#{counts['human']}件・不明#{counts['unknown']}件"
    )
  end
end
