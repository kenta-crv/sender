class ClickTrackingController < ApplicationController
  skip_before_action :verify_authenticity_token

  def redirect
    tracking = ClickTrackingLink.find_by(
      token: params[:token]
    )

    if tracking.blank?
      render plain: 'Invalid tracking link',
             status: :not_found
      return
    end

    tracking.increment!(:clicked_count)

    tracking.update!(
      last_clicked_at: Time.current
    )

    ClickLog.create!(
      click_tracking_link: tracking,
      ip: request.remote_ip,
      user_agent: request.user_agent
    )

    redirect_to tracking.target_url
  end
end