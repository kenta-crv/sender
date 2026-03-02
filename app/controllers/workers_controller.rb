class WorkersController < ApplicationController
  before_action :authenticate_worker!

  def show
    @worker = Worker.find(params[:id])
    @stats  = @worker.stats_summary
  end
end