class TopsController < ApplicationController
  before_action :set_breadcrumbs
  before_action :set_columns, only: [:index, :cargo, :security, :construction, :cleaning, :event, :logistics, :app, :ads]

  def index; end
  def cargo; end
  def security; end
  def construction; end
  def cleaning; end
  def event; end
  def logistics; end
  def app; end
  def ads; end

  private

  def set_columns
    @columns = Column.order(created_at: :desc).limit(3)
  end

  def set_breadcrumbs
    add_breadcrumb 'トップ', root_path

    label = LpDefinition.label(action_name)
    add_breadcrumb label, request.path if label
  end
end
