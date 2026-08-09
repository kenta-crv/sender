# frozen_string_literal: true

class Clients::OmniauthCallbacksController < Devise::OmniauthCallbacksController
  def google_oauth2
    handle_auth("Google")
  end

  def microsoft_graph
    handle_auth("Microsoft")
  end

  def failure
    redirect_to after_omniauth_failure_path_for(:client),
                alert: t("okurite.auth.oauth_failure", default: "外部アカウントでのログインに失敗しました。")
  end

  private

  def handle_auth(kind)
    auth = request.env["omniauth.auth"]
    @client = Client.from_omniauth(auth)

    if @client.persisted?
      @client.ensure_trial_subscription!
      sign_in_and_redirect @client, event: :authentication
      set_flash_message(:notice, :success, kind: kind) if is_navigational_format?
    else
      session["devise.#{auth.provider}_data"] = auth.except("extra")
      redirect_to new_client_registration_path,
                  alert: @client.errors.full_messages.to_sentence.presence ||
                         t("okurite.auth.oauth_failure", default: "外部アカウントでのログインに失敗しました。")
    end
  rescue ArgumentError => e
    redirect_to new_client_session_path,
                alert: e.message.presence || t("okurite.auth.oauth_failure", default: "外部アカウントでのログインに失敗しました。")
  end

  def after_sign_in_path_for(_resource)
    dashboard_index_path
  end
end
