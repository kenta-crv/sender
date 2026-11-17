# 受信した返信の一覧（管理者のみ）。自動受付と人の返信をタブで分けて表示する。
class Dashboard::RepliesController < ApplicationController
  before_action :require_admin!

  def index
    @tab = InboundReply::CLASSIFICATIONS.key?(params[:tab]) ? params[:tab] : 'human'
    @counts = InboundReply::CLASSIFICATIONS.keys.index_with { |c| InboundReply.with_final(c).count }
    @replies = InboundReply.with_final(@tab).includes(:customer)
                           .order(received_at: :desc).page(params[:page]).per(30)
  end

  # 判定の誤りを手で直す
  def reclassify
    reply = InboundReply.find(params[:id])
    to = params[:to].to_s
    reply.update!(manual_classification: InboundReply::CLASSIFICATIONS.key?(to) ? to : nil)
    redirect_to dashboard_replies_path(tab: params[:tab]), notice: '分類を変更しました'
  end

  private

  def require_admin!
    redirect_to root_path unless acting_as_admin?
  end
end
