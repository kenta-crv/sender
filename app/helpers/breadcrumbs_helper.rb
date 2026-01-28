module BreadcrumbsHelper
  def breadcrumbs
    @breadcrumbs ||= []
  end

  def add_breadcrumb(name, path = nil)
    breadcrumbs << { name: name, path: path }
  end
end
