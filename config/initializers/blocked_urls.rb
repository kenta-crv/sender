# frozen_string_literal: true

# NGブラックリスト（URL部分一致フィルター）
# プラットフォームサイトへの大量配信を防止するため、
# URLにこれらの文字列が含まれている場合は送信・検出をスキップする。
#
# 追加・編集する場合はこのファイルを変更し、Railsを再起動してください。
BLOCKED_URL_PATTERNS = %w[
  indeed.com
  indeed.jp
  doda.jp
  engage.jp
  en-japan.com
  mynavi.jp
  rikunabi.com
  hellowork.mhlw.go.jp
  baitoru.com
  townwork.net
  wantedly.com
  green-japan.com
  type.jp
  daijob.com
  jobigyou.com
  google.com
  google.co.jp
  facebook.com
  twitter.com
  instagram.com
  amazon.co.jp
  amazon.com
  rakuten.co.jp
  yahoo.co.jp
  linkedin.com
  youtube.com
  wikipedia.org
  tabelog.com
  hotpepper.jp
  suumo.jp
  homes.co.jp
  athome.co.jp
  mercari.com
  crowdworks.jp
  lancers.jp
  coconala.com
].freeze
