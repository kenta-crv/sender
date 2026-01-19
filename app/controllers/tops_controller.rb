class TopsController < ApplicationController
  before_action :set_breadcrumbs
  before_action :set_columns, only: [:index, :cargo, :security, :construction, :cleaning, :event, :logistics, :app, :ads]

  def index
    @contract = Contract.new
  end
  def cargo
    @contract = Contract.new
  end
  def security
    @contract = Contract.new
  end
  def construction
    @contract = Contract.new
  end
  def cleaning
    @contract = Contract.new
  end
  def event
    @contract = Contract.new
  end
  def logistics
    @contract = Contract.new
  end
  def app
    @contract = Contract.new
  end
  def ads
    @contract = Contract.new
  end
  def short
    @contract = Contract.new
  end
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
