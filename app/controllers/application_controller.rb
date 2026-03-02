class ApplicationController < ActionController::Base
  include MetaTags::ControllerHelper

  before_action :init_breadcrumbs
  helper_method :breadcrumbs

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
end

  def init_breadcrumbs
    @breadcrumbs = []
  end
end