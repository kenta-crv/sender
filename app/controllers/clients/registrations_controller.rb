# frozen_string_literal: true

class Clients::RegistrationsController < Devise::RegistrationsController
  before_action :configure_sign_up_params, only: [:create]
  before_action :configure_account_update_params, only: [:update]

  def create
    super
  end

  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [
      :company,
      :name,
      :tel,
      :address,
      :url
    ])
  end

  def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [
      :company,
      :name,
      :tel,
      :address,
      :url
    ])
  end

  def after_sign_up_path_for(resource)
    plans_path
  end
end