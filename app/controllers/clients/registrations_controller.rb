# frozen_string_literal: true

class Clients::RegistrationsController < Devise::RegistrationsController
  before_action :reject_client_auth_while_admin!, only: [:new, :create]
  before_action :configure_account_update_params, only: [:update]

  def new
    session[:client_oauth_intent] = "sign_up"
    super
  end

  def create
    build_resource(sign_up_params)
    resource.registration_ip = request.remote_ip
    super do |client|
      RegistrationAbuseGuard.track!(client) if client.persisted?
    end
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

  def after_sign_up_path_for(_resource)
    dashboard_index_path
  end

  def after_inactive_sign_up_path_for(_resource)
    dashboard_index_path
  end
end
