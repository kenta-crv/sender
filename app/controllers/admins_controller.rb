class AdminsController < ApplicationController
  before_action :authenticate_admin!

  def show
    # routes.rb で resources :admins としているので params[:id] で取得
    @admin = Admin.find(params[:id])
    @workers = Worker.includes(:calls).all
  end
end