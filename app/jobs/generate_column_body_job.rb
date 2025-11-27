class GenerateColumnBodyJob < ApplicationJob
  queue_as :article_generation
  
  def perform(column_id)
    # 修正: find を find_by に変更し、レコードが存在しない場合は警告を出して終了する
    column = Column.find_by(id: column_id)
    
    unless column
      # レコードが見つからない場合は正常終了させ、リトライキューに移動するのを防ぐ
      Rails.logger.warn("【警告】記事本文生成ジョブ: ID=#{column_id} の記事が見つかりません。スキップします。")
      return 
    end

    # ここから元の処理
    # 🚨 対策: APIレート制限回避のため、10秒間待機
    sleep(10) 

    begin
      column.update!(status: "creating")
      
      # GptArticleGenerator に修正が適用されていることを確認
      body = GptArticleGenerator.generate_body(column) 
      
      if body.present?
        column.update!(body: body, status: "completed")
        Rails.logger.info("記事本文の生成が完了しました。ColumnID: #{column_id}")
      else
        # GPT生成自体が失敗した場合は、リトライが必要なエラーとして引き続き raise する
        raise StandardError.new("GPT本文生成失敗 (APIエラー/タイムアウト) ColumnID: #{column_id}")
      end
      
    rescue => e
      Rails.logger.error("記事生成ジョブ実行エラー: #{e.message}")
      # その他のエラー（DBエラー、API通信エラーなど）はリトライ対象とする
      raise 
    end
  end
end