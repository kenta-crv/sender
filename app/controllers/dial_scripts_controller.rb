class DialScriptsController < ApplicationController
  before_action :authenticate_admin!
  before_action :set_dial_script, only: [:show, :edit, :update, :destroy]

  def index
    @dial_scripts = DialScript.order(:id)
  end

  def show
    @dial_utterance = DialUtterance.new
    @dial_faq = DialFaq.new
    @unknown_utterances = @dial_script.dial_unknown_utterances.order(created_at: :desc).limit(50)
  end

  def new
    @dial_script = DialScript.new(repeat_text: DialScript::REPEAT_TEXT)
  end

  def create
    @dial_script = DialScript.new(dial_script_params)
    apply_bank_fields!(@dial_script)
    if @dial_script.save
      redirect_to @dial_script, notice: '原稿を作成しました。'
    else
      render :new
    end
  end

  def edit
  end

  def update
    @dial_script.assign_attributes(dial_script_params)
    apply_bank_fields!(@dial_script)
    if @dial_script.save
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
    permitted = params.require(:dial_script).permit(
      :name, :greeting_text, :purpose_text, :wait_text, :repeat_text,
      :smalltalk_text, :clarify_text, :clarify_alt_text, :clarify_simple_text,
      :callback_text,
      status_texts: {}
    )
    hash = permitted.to_h
    if hash['status_texts']
      hash['status_texts'] = hash['status_texts'].slice(*Call::AI_STATUS_ITEMS).to_json
    end
    hash
  end

  def apply_bank_fields!(script)
    raw = params.require(:dial_script)
    DialScript::BANK_EDIT_KEYS.each do |key|
      field = "bank_#{key}"
      next unless raw.key?(field)

      script.assign_bank_field(key, raw[field])
    end
  end
end
