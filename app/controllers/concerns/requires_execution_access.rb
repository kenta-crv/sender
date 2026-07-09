# frozen_string_literal: true

module RequiresExecutionAccess
  extend ActiveSupport::Concern

  class_methods do
    def require_execution_access!(only: nil)
      before_action :ensure_execution_access!, only: only
    end
  end

  private

  def ensure_execution_access!
    return if admin_signed_in?
    return unless client_signed_in?

    unless current_client.confirmed?
      redirect_to dashboard_index_path,
                  alert: "本番実行にはメールアドレスの確認が必要です。登録メール内のリンクをクリックしてください。"
      return
    end

    return if current_client.payment_method_registered?

    session[:execution_return_to] = request.fullpath if request.get? || request.post?
    redirect_to checkout_confirmation_path(plan_type: "setup_card"),
                alert: "本番実行にはお支払い方法の登録が必要です。"
  end
end
