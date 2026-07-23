class FunnelEventsController < ApplicationController
  skip_before_action :verify_authenticity_token
  skip_before_action :check_trial_expiration

  ALLOWED_PAGES        = FunnelEvent::PAGES.freeze
  ALLOWED_EVENT_TYPES  = FunnelEvent::EVENT_TYPES.freeze
  BOT_UA_PATTERN       = /bot|crawl|spider|slurp|facebookexternalhit|preview|headless|wget|curl|python-requests|scrapy/i
  DEDUP_WINDOW         = 10.seconds

  def create
    page       = params[:page].to_s
    event_type = params[:event_type].to_s
    user_agent = request.user_agent.to_s

    unless ALLOWED_PAGES.include?(page) && ALLOWED_EVENT_TYPES.include?(event_type)
      head :unprocessable_entity
      return
    end

    if bot_request?(user_agent)
      head :ok
      return
    end

    tracking_link = ClickTrackingLink.find_by(token: params[:ftkn].to_s.strip.presence)
    ip = request.remote_ip

    if duplicate_event?(page: page, event_type: event_type, ip: ip, click_tracking_link_id: tracking_link&.id)
      head :ok
      return
    end

    FunnelEvent.create!(
      page:                  page,
      event_type:            event_type,
      time_spent_seconds:    params[:time_spent_seconds].to_i.clamp(0, 86_400),
      ip:                    ip,
      user_agent:            user_agent.truncate(500),
      click_tracking_link_id: tracking_link&.id
    )

    head :ok
  rescue => e
    Rails.logger.error "FunnelEvent create error: #{e.message}"
    head :internal_server_error
  end

  private

  def bot_request?(user_agent)
    user_agent.blank? || user_agent.match?(BOT_UA_PATTERN)
  end

  def duplicate_event?(page:, event_type:, ip:, click_tracking_link_id:)
    FunnelEvent.where(
      page: page,
      event_type: event_type,
      ip: ip,
      click_tracking_link_id: click_tracking_link_id,
      created_at: DEDUP_WINDOW.ago..
    ).exists?
  end
end
