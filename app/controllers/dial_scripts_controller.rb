class DialScriptsController < ApplicationController
  before_action :set_dial_script, only: [:show, :edit, :update, :destroy]

  def index
    @dial_scripts = DialScript.order(:id)
  end

  def show
    @dial_utterance = DialUtterance.new
  end

  def new
    @dial_script = DialScript.new
  end

  def create
    @dial_script = DialScript.new(dial_script_params)
    if @dial_script.save
      redirect_to @dial_script, notice: '原稿を作成しました。'
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @dial_script.update(dial_script_params)
      redirect_to @dial_script, notice: '原稿を更新しました。'
    else
      render :edit
    end
  end

  def destroy
    @dial_script.destroy
    redirect_to dial_scripts_path, notice: '原稿を削除しました。'
  end

  private

  def set_dial_script
    @dial_script = DialScript.find(params[:id])
  end

  def dial_script_params
    params.require(:dial_script).permit(
      :name, :css, :greeting_text, :purpose_text, :wait_text, :absent_text,
      :rejection_text, :no_human_text, :repeat_text, :closing_text
    )
  end
end
