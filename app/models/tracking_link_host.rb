# frozen_string_literal: true

# メール本文の /l/:token ・ /u/:token を載せてよいホスト。
# ブランド表示は Submission#url のホストを使うが、そのホストで /l/ /u/ が
# Okurite に届く（自前 or nginx プロキシ）ことが必須。
# 未登録ホストで送ると 404 のリンクが顧客に届くため、許可リスト外は拒否する。
module TrackingLinkHost
  ALLOWED = %w[
    okurite.pro
    drafity.pro
    meetia.pro
    www.meetia.pro
    j-work.jp
  ].freeze

  module_function

  def allowed?(host)
    host.present? && ALLOWED.include?(host.to_s.downcase)
  end

  def assert_allowed!(host)
    return if allowed?(host)

    raise UnsupportedHostError,
          "計測リンク非対応ホストです: #{host.presence || '(blank)'}。" \
          " /l/ /u/ を Okurite へ届ける nginx 設定を追加し、" \
          "TrackingLinkHost::ALLOWED にも登録してから送信してください。"
  end

  class UnsupportedHostError < StandardError; end
end
