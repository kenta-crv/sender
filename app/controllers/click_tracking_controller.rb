class ClickTrackingController < ApplicationController
  skip_before_action :verify_authenticity_token

  STAY_DEDUP = 10.minutes
  STAY_ALLOWED_ORIGINS = TrackingLinkHost::ALLOWED.map { |host| "https://#{host}" }.freeze

  def redirect
    tracking = ClickTrackingLink.find_by(
      token: params[:token].to_s.strip.presence
    )

    if tracking.present?
      destination = destination_url(tracking)
      redirect_to(destination.presence || root_url) and return
    end

    # 文字ページは出さず、トップへ飛ばす
    redirect_to root_url
  end

  # LP で可視3秒以上滞在したときだけクリックとして記録する。
  def stay
    apply_stay_cors
    return head(:ok) if request.options?

    tracking = ClickTrackingLink.find_by(token: params[:token].to_s.strip.presence)
    return head(:ok) if tracking.blank?

    user_agent = request.user_agent.to_s
    return head(:ok) if user_agent.blank? || user_agent.match?(ApplicationController::FTKN_BOT_UA_PATTERN)

    ip = request.remote_ip
    if tracking.click_logs.where(ip: ip, created_at: STAY_DEDUP.ago..).exists?
      return head(:ok)
    end

    tracking.record_click!(ip: ip, user_agent: user_agent)
    head :ok
  end

  private

  def apply_stay_cors
    origin = request.origin.presence
    return unless origin.present? && STAY_ALLOWED_ORIGINS.include?(origin)

    response.set_header("Access-Control-Allow-Origin", origin)
    response.set_header("Access-Control-Allow-Methods", "POST, OPTIONS")
    response.set_header("Access-Control-Allow-Headers", "Content-Type")
    response.set_header("Vary", "Origin")
  end

  def destination_url(tracking)
    return if tracking.target_url.blank?

    uri = URI.parse(tracking.target_url)
    existing = URI.decode_www_form(uri.query || '')
    existing.reject! { |key, _| key == 'ftkn' }
    existing << ['ftkn', tracking.token]
    uri.query = URI.encode_www_form(existing)
    uri.to_s
  rescue URI::InvalidURIError, TypeError, ArgumentError
    tracking.target_url.presence
  end
end
