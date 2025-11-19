class ColumnsController < ApplicationController
  #before_action :authenticate_admin!, except: [:index, :show]

def index
  if params[:status].present?
    @columns = Column.where(status: params[:status]).where.not(status: "draft").order(created_at: :desc)
  else
    @columns = Column.where.not(status: "draft").order(created_at: :desc)
  end
end

def show
  @column = Column.find_by(id: params[:id])

  if @column.nil?
    redirect_to columns_path, alert: "指定された記事が見つかりませんでした。"
    return
  end

  # bodyがnilの場合に備えて、フォールバックテキストを設定
  content_to_process = @column.body.present? ? @column.body :
    "## 記事はまだ生成されていません。\n\n[編集]画面からテーマ生成を行い、[承認]ボタンを押して本文生成ジョブを実行してください。"

  # 不要な inline style や <span> タグを除去
  sanitized_body = content_to_process.gsub(/<span[^>]*>|<\/span>/, '')
                                     .gsub(/ style=\"[^\"]*\"/, '')

  @headings = []
  @column_body_with_ids = sanitized_body.gsub(/<(h[2-4])>(.*?)<\/\1>/m) do |match|
    if match =~ /<(h[2-4])>(.*?)<\/\1>/m
      tag = $1
      text = $2
      idx = @headings.size
      @headings << { tag: tag, text: text, id: "heading-#{idx}", level: tag[1].to_i }
      "<#{tag} id='heading-#{idx}'>#{text}</#{tag}>"
    else
      match
    end
  end
end


  def new
    @column = Column.new
  end

  def create
    @column = Column.new(column_params)
    if @column.save
      redirect_to columns_path
    else
      render 'new'
    end
  end

  def edit
    @column = Column.find(params[:id])
    add_breadcrumb "記事編集", edit_column_path
  end

  def destroy
    @column = Column.find(params[:id])
    @column.destroy
     redirect_to columns_path
  end

  def update
    @column = Column.find(params[:id])
    if @column.update(column_params)
      redirect_to columns_path
    else
      render 'edit'
    end
  end

    # ▼ ① Gemini自動生成（UIボタンから呼ばれる）
  def generate_gemini
    batch = params[:batch] || 5
    created = GeminiColumnGenerator.generate_columns(batch_count: batch.to_i)

    redirect_to draft_columns_path, notice: "#{created}件生成しました"
  end


  # ▼ ② ドラフト一覧
  def draft
    @columns = Column.where(status: "draft").order(created_at: :desc)
  end

def approve
  @column = Column.find(params[:id])
  unless @column.approved?
    @column.update!(status: "approved")
  end
  GenerateColumnBodyJob.perform_later(@column.id)
  redirect_to columns_path, notice: "承認しました。本文生成を開始します。"
end

  private
  def column_params
    params.require(:column).permit(
      :title, #タイトル
      :file,  #写真
      :choice,  #カテゴリー
      :keyword, #キーワード
      :description, #説明
      :body #本文
      )
    end
  end
