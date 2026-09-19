class DialUtterancesController < ApplicationController
  before_action :set_dial_script

  def create
    @dial_utterance = @dial_script.dial_utterances.new(dial_utterance_params)
    if @dial_utterance.save
      redirect_to @dial_script, notice: '想定の返事を追加しました。'
    else
      @dial_script.reload
      render 'dial_scripts/show'
    end
  end

  def destroy
    utterance = @dial_script.dial_utterances.find(params[:id])
    utterance.destroy
    redirect_to @dial_script, notice: '想定の返事を削除しました。'
  end

  private

  def set_dial_script
    @dial_script = DialScript.find(params[:dial_script_id])
  end

  def dial_utterance_params
    params.require(:dial_utterance).permit(:phrase, :script_key)
  end
end
