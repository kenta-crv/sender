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

  def init_breadcrumbs
    @breadcrumbs = []
  end
end