class GenerateColumnBodyJob < ApplicationJob
  queue_as :default

  def perform(column_id)
    column = Column.find(column_id)
    return unless column.status == "approved"

    body = GptArticleGenerator.generate_body(column)

    if body.present?
      column.update!(body: body)
    else
      Rails.logger.error("GPT本文生成失敗 ColumnID: #{column.id}")
    end
  end
end
