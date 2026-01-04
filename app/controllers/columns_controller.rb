class ColumnsController < ApplicationController
  # before_action :authenticate_admin!, except: [:index, :show]
  before_action :set_column, only: [:show, :edit, :update, :destroy, :approve]
  before_action :set_breadcrumbs

  def index
    columns = Column.where.not(status: "draft")
    columns = columns.where(status: params[:status]) if params[:status].present?

    if params[:genre].present?
      # Columnモデルの定数 GENRE_MAPPING を参照
      allowed_genres = Column::GENRE_MAPPING[params[:genre]] || [params[:genre]]
      columns = columns.where(genre: allowed_genres)
    end

    @columns = columns.order(updated_at: :desc)
  end

  # GET /:genre/columns/:id (実際は :id に code が入る)
  def show
    # --- SEO対策: 正規URLへのリダイレクト ---
    # genre が存在し、かつルーティング制約(cargo|security等)に合致する場合のみ階層ありURLを使用
    is_valid_genre = @column.genre.present? && @column.genre.match?(/cargo|security|cleaning|app|construction/)
    
    correct_path = if is_valid_genre
                     nested_columns_path(genre: @column.genre, id: @column)
                   else
                     column_path(@column)
                   end

    # 現在のURLパスが正規のパスと異なる場合のみ、301リダイレクトを実行
    if request.path != correct_path
      return redirect_to correct_path, status: :moved_permanently
    end

    markdown_body =
      @column.body.presence ||
      "## 記事はまだ生成されていません。\n\n[編集]画面からテーマ生成を行い、[承認]ボタンを押して本文生成ジョブを実行してください。"

    raw_html_body = Kramdown::Document.new(markdown_body).to_html

    sanitized_html_body = raw_html_body
      .gsub(/<span[^>]*>|<\/span>/, '')
      .gsub(/ style=\"[^\"]*\"/, '')

    @headings = []

    @column_body_with_ids =
      sanitized_html_body.gsub(/<(h[2-4])>(.*?)<\/\1>/m) do
        tag  = Regexp.last_match(1)
        text = Regexp.last_match(2)

        idx = @headings.size
        @headings << {
          tag: tag,
          text: text,
          id: "heading-#{idx}",
          level: tag[1].to_i
        }

        "<#{tag} id='heading-#{idx}'>#{text}</#{tag}>"
      end
  end

  def new
    @column = Column.new
  end

  def create
    @column = Column.new(column_params)
    if @column.save
      redirect_to columns_path, notice: "作成しました"
    else
      render 'new'
    end
  end

  def edit
    add_breadcrumb "記事編集", edit_column_path(@column)
  end

  def update
    if @column.update(column_params)
      redirect_to columns_path, notice: "更新しました"
    else
      render 'edit'
    end
  end

  def destroy
    @column.destroy
    redirect_to columns_path, notice: "削除しました"
  end

  def generate_gemini
    batch = params[:batch] || 20
    created = GeminiColumnGenerator.generate_columns(batch_count: batch.to_i)
    redirect_to draft_columns_path, notice: "#{created}件生成しました"
  end

  def draft
    @columns = Column.where(status: "draft").order(created_at: :desc)
  end

  def approve
    unless @column.approved?
      @column.update!(status: "approved")
    end
    GenerateColumnBodyJob.perform_later(@column.id)
    redirect_to columns_path, notice: "承認しました。本文生成を開始します。"
  end

  def bulk_update_drafts
    column_ids = params[:column_ids]

    unless column_ids.present?
      redirect_to draft_columns_path, alert: "操作対象のドラフトが選択されていません。"
      return
    end

    case params[:action_type]
    when "approve_bulk"
      columns = Column.where(id: column_ids)
      columns.each do |column|
        unless column.approved?
          column.update!(status: "approved")
          GenerateColumnBodyJob.perform_later(column.id)
        end
      end
      redirect_to columns_path, notice: "#{columns.count}件のドラフトを承認しました。"

    when "delete_bulk"
      count = Column.where(id: column_ids).destroy_all
      redirect_to draft_columns_path, notice: "#{count}件のドラフトを削除しました。"

    else
      redirect_to draft_columns_path, alert: "無効な操作が選択されました。"
    end
  end

  private

  def set_column
    # friendly.find を使うことで、ID数値でも英字codeでも検索を可能にします
    @column = Column.friendly.find(params[:id])
  end

  def set_breadcrumbs
    add_breadcrumb 'トップ', root_path

    genre_key = @column&.genre.present? ? @column.genre : params[:genre]
    
    if defined?(LpDefinition)
      label = LpDefinition.label(genre_key)
      add_breadcrumb label, "/#{genre_key}" if label
    end

    add_breadcrumb @column.title if action_name == 'show' && @column
  end

  def column_params
    params.require(:column).permit(
      :title, :file, :choice, :keyword, :description, :genre, :code, :body, :status
    )
  end
end