class SubmissionsController < ApplicationController
  def index 
    @submission = Submission.all
  end

  def show 
    @submission = Submission.find(params[:id])
  end

  def new
    @submission = Submission.new
  end

  def create
    @submission = Submission.new(submission_params)
    if @submission.save
       redirect_to submissions_path
    else
      render 'new'
    end
  end

  def edit
    @submission = Submission.find(params[:id])
  end

  def destroy
    @submission = Submission.find(params[:id])
    @submission.destroy
    redirect_to submissions_path
  end

  def update
    @submission = Submission.find(params[:id])
    if @submission.update(submission_params)
      redirect_to submissions_path
    else
      render 'edit'
    end
  end
  private

  def submission_params
    params.require(:submission).permit(
      :headline, #案件名
      :from_company, #会社名
      :person, #担当者
      :person_kana, #タントウシャ
      :from_tel, #電話番号
      :from_fax, #FAX番号
      :from_mail, #メールアドレス
      :url, #HP
      :address, #住所
      :title, #件名
      :content #本文
    )
  end

end
