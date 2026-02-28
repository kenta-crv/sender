class SubmissionsController < ApplicationController
  before_action :set_submission, only: [:show, :edit, :update, :destroy]

  def index
    @submissions = Submission.order(created_at: :desc)
  end

  def show
  end

  def new
    @submission = Submission.new
  end

  def create
    @submission = Submission.new(submission_params)
    if @submission.save
      redirect_to submissions_path, notice: '送信内容を作成しました。'
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @submission.update(submission_params)
      redirect_to submissions_path, notice: '送信内容を更新しました。'
    else
      render :edit
    end
  end

  def destroy
    @submission.destroy
    redirect_to submissions_path, notice: '送信内容を削除しました。'
  end

  private

  def set_submission
    @submission = Submission.find(params[:id])
  end

  def submission_params
    params.require(:submission).permit(
      :headline, :company, :person, :person_kana,
      :tel, :fax, :address, :email, :url, :title, :content
    )
  end
end
