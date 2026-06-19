class ProblemsController < ApplicationController
    #before_action :authenticate_admin!, only: [:index, :destroy, :send_mail]
    def index
      @problems = Problem.order(created_at: "DESC").page(params[:page])
    end
  
    def new
      @problem = Problem.new
    end
  
def create
  @problem = Problem.new(problem_params)

  if @problem.save
    flash[:notice] = "送信完了しました"
    redirect_to root_path
    ProblemMailer.report_email(@problem).deliver # 管理者に通知
  else
    render :new
  end
end

    def show
      @problem = Problem.find(params[:id])
    end
  
    def edit
      @problem = Problem.find(params[:id])
    end

    def destroy
      @problem = Problem.find(params[:id])
      @problem.destroy
      redirect_to problems_path, alert:"削除しました"
    end
  
    def update
      @problem = Problem.find(params[:id])
    
      if @problem.update(problem_params)
        redirect_to root_path
      else
        # 更新が失敗した場合の処理
        render :edit
      end
    end

    private
    def problem_params
      params.require(:problem).permit(
      :company, #会社名
      :email, #メールアドレス
      :body,
      :photo
      )
    end
end
