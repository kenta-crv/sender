# frozen_string_literal: true

class Clients::RegistrationsController < Devise::RegistrationsController

  # =========================
  # Sign Up (create)
  # =========================
  def configure_sign_up_params
    devise_parameter_sanitizer.permit(:sign_up, keys: [
      :company,
      :name,
      :tel,
      :address,
      :url
    ])
  end

  # =========================
  # Account Update
  # =========================
  def configure_account_update_params
    devise_parameter_sanitizer.permit(:account_update, keys: [
      :company,
      :name,
      :tel,
      :address,
      :url
    ])
  end

  # Devise hooks
  before_action :configure_sign_up_params, only: [:create]
  before_action :configure_account_update_params, only: [:update]

  # =========================
  # Redirect after sign up
  # =========================
  def after_sign_up_path_for(resource)
    plans_path
  end

end