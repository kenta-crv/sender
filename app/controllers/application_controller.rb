class ApplicationController < ActionController::Base
  include MetaTags::ControllerHelper

  FTKN_BOT_UA_PATTERN = /bot|crawl|spider|slurp|facebookexternalhit|preview|headless|wget|curl|python-requests|scrapy/i

  before_action :init_breadcrumbs
  helper_method :breadcrumbs
  before_action :check_trial_expiration
  before_action :record_ftkn_landing_click
  

  def breadcrumbs
    @breadcrumbs
  end

  def add_breadcrumb(label, path = nil)
    @breadcrumbs << { label: label, path: path }
  end

  private
def after_sign_in_path_for(resource)
  case resource
  when Admin
    dashboard_index_path(resource)
  when Client
    # Always redirect to dashboard for Clients, ignore stored location
    dashboard_index_path
  when Worker
    # ↓ ここは「s」なし！ (resource)を忘れずに
    worker_path(resource)
  else
    root_path
  end
end

  def init_breadcrumbs
    @breadcrumbs = []
  end
 
  def check_trial_expiration
    return unless current_client.present?
    current_client.check_and_upgrade_expired_trial
  end

  def delivery_filter_client_id
    return current_client.id if client_signed_in?
    return params[:client_id].presence if admin_signed_in?

    nil
  end
  helper_method :delivery_filter_client_id

  def delivery_filter_admin_id
    return current_admin.id if admin_signed_in?

    nil
  end
  helper_method :delivery_filter_admin_id

  # Submission.url?ftkn=... 着地時にクリック履歴を記録する。
  # /l/:token 経由と二重にならないよう session で抑止する。
  def record_ftkn_landing_click
    token = params[:ftkn].to_s.strip.presence
    return if token.blank?

    user_agent = request.user_agent.to_s
    return if user_agent.blank? || user_agent.match?(FTKN_BOT_UA_PATTERN)

    session_key = ftkn_click_session_key(token)
    return if session[session_key]

    tracking = ClickTrackingLink.find_by(token: token)
    return if tracking.blank?

    tracking.record_click!(ip: request.remote_ip, user_agent: user_agent)
    session[session_key] = true
  rescue => e
    Rails.logger.error "ftkn landing click error: #{e.message}"
  end

  def ftkn_click_session_key(token)
    "ftkn_click_recorded_#{token}"
  end
end
