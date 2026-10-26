class DialFaqsController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_dial_script

  def create
    @dial_faq = @dial_script.dial_faqs.new(dial_faq_params)
    if @dial_faq.save
      redirect_to @dial_script, notice: 'FAQを追加しました。'
    else
      @dial_utterance = DialUtterance.new
      @unknown_utterances = @dial_script.dial_unknown_utterances.order(created_at: :desc).limit(50)
      render 'dial_scripts/show'
    end
  end

  def destroy
    faq = @dial_script.dial_faqs.find(params[:id])
    faq.destroy
    redirect_to @dial_script, notice: 'FAQを削除しました。'
  end

  private

  def set_dial_script
    @dial_script = DialScript.find(params[:dial_script_id])
  end

  def dial_faq_params
    params.require(:dial_faq).permit(:question, :answer, :phrases)
  end
end
