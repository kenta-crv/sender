class ApplicationController < ActionController::Base
  include MetaTags::ControllerHelper

  before_action :init_breadcrumbs
  helper_method :breadcrumbs
  before_action :check_trial_expiration
  

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
    admin_path(resource)
  when Worker
    # ↓ ここは「s」なし！ (resource)を忘れずに
    worker_path(resource) 
  else
    root_path
  end
    if resource.is_a?(Client)
    # routesにある「clients GET /clients(.:format)」を参照
    return clients_path
  end
end

  def init_breadcrumbs
    @breadcrumbs = []
  end
 
  def check_trial_expiration
    return unless current_client.present?
    current_client.check_and_upgrade_expired_trial
  end

end