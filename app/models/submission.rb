class Submission < ApplicationRecord
  belongs_to :client, optional: true
  has_many :form_submission_batches, dependent: :destroy
  has_many :click_tracking_links, dependent: :destroy

  validate :url_host_must_support_tracking_links, if: -> { url.present? }

  private

  def url_host_must_support_tracking_links
    return if Rails.env.development? || Rails.env.test?

    host = URI.parse(url).host
    return if host.blank?
    return if TrackingLinkHost.allowed?(host)

    errors.add(
      :url,
      "のホスト「#{host}」は計測リンク（/l/ /u/）非対応です。" \
      "nginx で Okurite へプロキシし TrackingLinkHost::ALLOWED に追加してから保存してください。"
    )
  rescue URI::InvalidURIError
    errors.add(:url, "の形式が不正です")
  end
end
