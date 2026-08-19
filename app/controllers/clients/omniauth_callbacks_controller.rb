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
    if admin_signed_in?
      redirect_to dashboard_index_path,
                  alert: t("okurite.auth.admin_session_blocks_client",
                           default: "管理者でログイン中です。企業アカウントの登録・ログインは、管理者をログアウトしてから行ってください。")
      return
    end

    auth = request.env["omniauth.auth"]
    intent = oauth_intent
    @client = Client.from_omniauth(auth, intent: intent)

    if @client.persisted?
      @client.ensure_trial_subscription!
      sign_in_and_redirect @client, event: :authentication
      if is_navigational_format?
        flash[:notice] =
          if intent == "sign_up"
            t("okurite.auth.oauth_signed_up", kind: kind, default: "%{kind}アカウントで登録しました。")
          else
            t("okurite.auth.oauth_success", kind: kind, default: "%{kind}アカウントでログインしました。")
          end
      end
    else
      session["devise.#{auth.provider}_data"] = auth.except("extra")
      redirect_to oauth_failure_path(intent),
                  alert: @client.errors.full_messages.to_sentence.presence ||
                         t("okurite.auth.oauth_failure", default: "外部アカウントでのログインに失敗しました。")
    end
  rescue ArgumentError => e
    redirect_to oauth_failure_path(oauth_intent),
                alert: e.message.presence || t("okurite.auth.oauth_failure", default: "外部アカウントでのログインに失敗しました。")
  end

  def oauth_intent
    return @oauth_intent if defined?(@oauth_intent)

    omniauth_params = request.env["omniauth.params"] || {}
    raw = omniauth_params["intent"].presence ||
          omniauth_params[:intent].presence ||
          session.delete(:client_oauth_intent)
    @oauth_intent = raw.to_s == "sign_up" ? "sign_up" : "sign_in"
  end

  def oauth_failure_path(intent)
    intent == "sign_up" ? new_client_session_path : new_client_registration_path
  end

  def after_sign_in_path_for(_resource)
    sign_out(:admin) if admin_signed_in?
    dashboard_index_path
  end
end
