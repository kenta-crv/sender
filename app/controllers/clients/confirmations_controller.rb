# frozen_string_literal: true

class Clients::ConfirmationsController < Devise::ConfirmationsController
  protected

  def after_confirmation_path_for(_resource_name, _resource)
    dashboard_index_path
  end
end
