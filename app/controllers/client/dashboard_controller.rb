class Client::DashboardController < ApplicationController
  before_action :authenticate_client!

  def index
  end
end
