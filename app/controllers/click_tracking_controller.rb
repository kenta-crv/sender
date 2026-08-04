class ClickTrackingController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :record_ftkn_landing_click

  def redirect
    tracking = ClickTrackingLink.find_by(
      token: params[:token].to_s.strip.presence
    )

    if tracking.present?
      tracking.record_click!(
        ip: request.remote_ip,
        user_agent: request.user_agent
      )
      session[ftkn_click_session_key(tracking.token)] = true

      destination = destination_url(tracking)
      redirect_to(destination.presence || root_url) and return
    end

    # 文字ページは出さず、トップへ飛ばす
    redirect_to root_url
  end

  private

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
