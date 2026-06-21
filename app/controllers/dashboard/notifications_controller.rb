module Dashboard
  class NotificationsController < ApplicationController
    before_action :authenticate_admin_or_client!
    before_action :set_notification, only: [:show, :update, :destroy]

    def index
      @notifications = notification_scope.order(created_at: :desc).page(params[:page]).per(20)
      @unread_count = notification_scope.unread.count
    end

    def show
    end

    def create
      # Notifications are typically created by the system, not by users
      redirect_to dashboard_notifications_path, alert: '通知はシステムにより作成されます'
    end

    def update
      if @notification.update(read_at: Time.current)
        redirect_to dashboard_notifications_path, notice: '通知を既読にしました'
      else
        redirect_to dashboard_notifications_path, alert: '通知の更新に失敗しました'
      end
    end

    def destroy
      @notification.destroy
      redirect_to dashboard_notifications_path, notice: '通知を削除しました'
    end

    def mark_all_as_read
      notification_scope.unread.update_all(read_at: Time.current)
      redirect_to dashboard_notifications_path, notice: 'すべての通知を既読にしました'
    end

    private

    def set_notification
      @notification = Notification.find(params[:id])
    end

    def notification_scope
      if admin_signed_in?
        Notification.all
      elsif client_signed_in?
        Notification.where(client_id: current_client.id)
      else
        Notification.none
      end
    end

    def authenticate_admin_or_client!
      unless admin_signed_in? || client_signed_in?
        redirect_to root_path, alert: 'アクセス権限がありません'
      end
    end
  end
end
