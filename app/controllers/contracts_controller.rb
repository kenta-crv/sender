class ContractsController < ApplicationController
    #before_action :authenticate_admin!, only: [:index, :destroy, :send_mail]
    def index
      @contracts = Contract.order(created_at: "DESC").page(params[:page])
    end
  
    def new
      @contract = Contract.new
    end
  
def create
  @contract = Contract.new(contract_params)

  if @contract.save
    flash[:notice] = "送信完了しました"
    redirect_to root_path
    ContractMailer.received_email(@contract).deliver # 管理者に通知
    ContractMailer.send_email(@contract).deliver # 送信者に通知
  else
    render :new
  end
end

    def show
      @contract = Contract.find(params[:id])
      @comment = Comment.new
    end
  
    def edit
      @contract = Contract.find(params[:id])
    end

    def destroy
      @contract = Contract.find(params[:id])
      @contract.destroy
      redirect_to contracts_path, alert:"削除しました"
    end
  
    def update
      @contract = Contract.find(params[:id])
    
      if @contract.update(contract_params)
        redirect_to root_path
      else
        # 更新が失敗した場合の処理
        render :edit
      end
    end

    private
    def contract_params
      params.require(:contract).permit(
      :company, #会社名
      :name, #担当者
      :tel, #電話番号
      :email, #メールアドレス
      :address, #所在地
      :url,
      :period, #導入時期
      :message, #備考
      )
    end
end
