class GenerateColumnBodyJob < ApplicationJob
  queue_as :article_generation

  def perform(column_id)
    column = Column.find_by(id: column_id)

    unless column
      Rails.logger.warn("【警告】記事本文生成ジョブ: ID=#{column_id} の記事が見つかりません。スキップします。")
      return
    end

    # APIレート制限対策（任意）
    sleep(10)

    begin
      column.update!(status: "creating")

      # 親記事なら GptPillarGenerator、それ以外は GptArticleGenerator
      body =
        if column.article_type == "pillar"
          GptPillarGenerator.generate_body(column)
        else
          GptArticleGenerator.generate_body(column)
        end

      if body.present?
        column.update!(body: body, status: "completed")
        Rails.logger.info("記事本文の生成が完了しました。ColumnID: #{column_id}")
      else
        raise StandardError.new("GPT本文生成失敗 (APIエラー/タイムアウト) ColumnID: #{column_id}")
      end

    rescue => e
      Rails.logger.error("記事生成ジョブ実行エラー: #{e.message}")
      raise
    end
  end
end
