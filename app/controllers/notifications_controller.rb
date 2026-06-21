class Dashboard::NotificationsController < ApplicationController
  before_action :authenticate_any!
  before_action :set_notification, only: [:show, :mark_as_read]

  def index
    @notifications = scoped_notifications.recent.page(params[:page]).per(20)
    @unread_count = scoped_notifications.unread.count
  end

  def show
    @notification = scoped_notifications.find(params[:id])
    @notification.mark_as_read! if @notification.unread?
  end

  def mark_as_read
    @notification.mark_as_read!
    redirect_to dashboard_notifications_path, notice: '通知を既読にしました'
  end

  def mark_all_as_read
    scoped_notifications.unread.update_all(read_at: Time.current)
    redirect_to dashboard_notifications_path, notice: '全ての通知を既読にしました'
  end

  private

  def set_notification
    @notification = scoped_notifications.find(params[:id])
  end

  def scoped_notifications
    if admin_signed_in?
      Notification.all
    elsif client_signed_in?
      Notification.for_client(current_client.id)
    else
      Notification.none
    end
  end

  def authenticate_any!
    redirect_to root_path unless admin_signed_in? || client_signed_in?
  end
end