class ApplicationController < ActionController::Base
  include MetaTags::ControllerHelper

  FTKN_BOT_UA_PATTERN = /bot|crawl|spider|slurp|facebookexternalhit|preview|headless|wget|curl|python-requests|scrapy/i

  before_action :init_breadcrumbs
  helper_method :breadcrumbs, :acting_as_admin?
  before_action :check_trial_expiration

  def breadcrumbs
    @breadcrumbs
  end

  def add_breadcrumb(label, path = nil)
    @breadcrumbs << { label: label, path: path }
  end

  def acting_as_admin?
    admin_signed_in? && !client_signed_in?
  end

  private

  def after_sign_in_path_for(resource)
    case resource
    when Admin
      sign_out(:client) if client_signed_in?
      dashboard_index_path(resource)
    when Client
      sign_out(:admin) if admin_signed_in?
      dashboard_index_path
    when Worker
      worker_path(resource)
    else
      root_path
    end
  end

  def reject_client_auth_while_admin!
    return unless admin_signed_in?

    redirect_to dashboard_index_path,
                alert: t("okurite.auth.admin_session_blocks_client",
                         default: "管理者でログイン中です。企業アカウントの登録・ログインは、管理者をログアウトしてから行ってください。")
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
    return params[:client_id].presence if acting_as_admin?

    nil
  end
  helper_method :delivery_filter_client_id

  def delivery_filter_admin_id
    return current_admin.id if acting_as_admin?

    nil
  end
  helper_method :delivery_filter_admin_id

end
