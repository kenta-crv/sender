# frozen_string_literal: true

class Clients::SessionsController < Devise::SessionsController
  before_action :reject_client_auth_while_admin!, only: [:new, :create]

  def new
    session[:client_oauth_intent] = "sign_in"
    super
  end

  # GET /resource/sign_in
  # def new
  #   super
  # end

  # POST /resource/sign_in
  # def create
  #   super
  # end

  # DELETE /resource/sign_out
  # def destroy
  #   super
  # end

  # protected

  # If you have extra params to permit, append them to the sanitizer.
  # def configure_sign_in_params
  #   devise_parameter_sanitizer.permit(:sign_in, keys: [:attribute])
  # end
end
