module ColumnsHelper
    # ジャンルごとの一覧リンクを作る
  def columns_index_link(genre_key, label_text = nil)
    return unless Column::GENRE_MAPPING.key?(genre_key)
    
    text = label_text || "#{genre_key.titleize} コラム一覧"
    link_to text, nested_columns_path(genre: genre_key), class: "btn btn-primary"
  end
end
