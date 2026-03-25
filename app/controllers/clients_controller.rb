class ClientsController < ApplicationController
  before_action :authenticate_client!
  before_action :set_client, only: %i[show edit update destroy]
  before_action :authorize_client!, only: %i[show edit update destroy]

  def index
    @clients = Client.all
  end

  def show
  end

  def new
    @client = Client.new
  end

  def edit
  end

  def create
    @client = Client.new(client_params)
    if @client.save
      redirect_to @client, notice: "Client was successfully created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @client.update(client_params)
      redirect_to @client, notice: "Client was successfully updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @client.destroy
    redirect_to clients_url, notice: "Client was successfully deleted."
  end

  private

  def set_client
    @client = Client.find(params[:id])
  end

  def authorize_client!
    return if @client == current_client

    redirect_to root_path, alert: "権限がありません。"
  end

  def client_params
    params.require(:client).permit(:name, :email, :company, :domain, :api_key, :password, :password_confirmation)
  end
end
