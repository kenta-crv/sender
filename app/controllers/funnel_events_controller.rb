class FunnelEventsController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :check_trial_expiration

  ALLOWED_PAGES        = FunnelEvent::PAGES.freeze
  ALLOWED_EVENT_TYPES  = FunnelEvent::EVENT_TYPES.freeze

  def create
    page       = params[:page].to_s
    event_type = params[:event_type].to_s

    unless ALLOWED_PAGES.include?(page) && ALLOWED_EVENT_TYPES.include?(event_type)
      head :unprocessable_entity
      return
    end

    tracking_link = ClickTrackingLink.find_by(token: params[:ftkn].to_s.strip.presence)

    FunnelEvent.create!(
      page:                  page,
      event_type:            event_type,
      time_spent_seconds:    params[:time_spent_seconds].to_i.clamp(0, 86_400),
      ip:                    request.remote_ip,
      user_agent:            request.user_agent&.truncate(500),
      click_tracking_link_id: tracking_link&.id
    )

    head :ok
  rescue => e
    Rails.logger.error "FunnelEvent create error: #{e.message}"
    head :internal_server_error
  end
end
