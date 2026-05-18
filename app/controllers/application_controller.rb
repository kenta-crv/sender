class ApplicationController < ActionController::Base
  include MetaTags::ControllerHelper

  before_action :init_breadcrumbs
  helper_method :breadcrumbs
  before_action :check_trial_expiration
  

  def breadcrumbs
    @breadcrumbs
  end

  def add_breadcrumb(label, path = nil)
    @breadcrumbs << { label: label, path: path }
  end

  private
  
  def after_sign_in_path_for(resource)
    case resource
    when Admin
      admin_dashboard_index_path(resource)
    when Client
      client_dashboard_index_path(resource)
    when Worker
      # ↓ ここは「s」なし！ (resource)を忘れずに
      worker_path(resource) 
    else
      root_path
    end
  end

  def init_breadcrumbs
    @breadcrumbs = []
  end
 
  def check_trial_expiration
    # 管理者ログイン時はチェックをスキップ
    return if respond_to?(:admin_signed_in?) && admin_signed_in?
    return unless current_client.present?
    
    # トライアルの判定とアップグレード処理を実行
    current_client.check_and_upgrade_expired_trial

    # 💡 処理実行後、クライアントのプランやトライアル状態を判定します。
    # ※ clientモデルの期限切れフラグ（例: expired? や trial_end?、あるいは特定のプラン名）に合わせて条件を調整してください。
    # ここでは一般的な「trial_expired?」というメソッドがある、またはプランが制限された状態を想定しています。
    if current_client.respond_to?(:trial_expired?) && current_client.trial_expired?
      # セッションを一度クリアしてダッシュボードやルートに戻し、アラートを表示します
      redirect_to root_path, alert: 'トライアル期間は終了しました。継続してご利用いただくにはプランの更新が必要です。'
    end
  end

end