module Batch
  class BlogGenerator
    def self.run_daily(daily_count = 34)
      Rails.logger.info("=== Blog generation start: #{Time.current} ===")

      daily_count.times do |i|
        Rails.logger.info("=== Processing #{i + 1}/#{daily_count} ===")

        # =====================
        # 1. タイトル生成
        # =====================
        GeminiColumnGenerator.generate_columns(batch_count: 1)

        column = Column.order(created_at: :desc).first
        unless column
          Rails.logger.error("タイトル生成失敗")
          next
        end

        # =====================
        # 2. 本文生成
        # =====================
        begin
          body = GptArticleGenerator.generate_body(column)

          if body.present?
            column.update!(body: body, status: "body_completed")
            Rails.logger.info("本文生成成功: #{column.id}")
          else
            column.update!(status: "failed")
            Rails.logger.error("本文生成失敗: #{column.id}")
          end
        rescue => e
          column.update!(status: "failed")
          Rails.logger.error("本文生成例外: #{e.message}")
        end

        sleep(1) # API負荷対策
      end

      Rails.logger.info("=== Blog generation end: #{Time.current} ===")
    end
  end
end
