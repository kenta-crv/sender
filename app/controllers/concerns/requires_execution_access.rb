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
    return if current_client.payment_method_registered?

    redirect_to plans_path, alert: "本番実行にはプラン選択とお支払い方法の登録が必要です。"
  end
end
