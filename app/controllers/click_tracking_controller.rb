class ClickTrackingController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :record_ftkn_landing_click

  def redirect
    tracking = ClickTrackingLink.find_by(
      token: params[:token]
    )

    if tracking.blank?
      render plain: 'Invalid tracking link',
             status: :not_found
      return
    end

    tracking.record_click!(
      ip: request.remote_ip,
      user_agent: request.user_agent
    )
    session[ftkn_click_session_key(tracking.token)] = true

    destination = begin
      uri = URI.parse(tracking.target_url)
      existing = URI.decode_www_form(uri.query || '')
      existing << ['ftkn', tracking.token]
      uri.query = URI.encode_www_form(existing)
      uri.to_s
    rescue URI::InvalidURIError
      tracking.target_url
    end

    redirect_to destination
  end
end