class DialUnknownUtterancesController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_dial_script

  def destroy
    row = @dial_script.dial_unknown_utterances.find(params[:id])
    row.destroy
    redirect_to @dial_script, notice: '未知発話ログを削除しました。'
  end

  private

  def set_dial_script
    @dial_script = DialScript.find(params[:dial_script_id])
  end
end
