class FormSubmissionBatch < ApplicationRecord
  belongs_to :submission, optional: true

  # customer_ids と error_log は JSON テキストとして保存
  def parsed_customer_ids
    JSON.parse(customer_ids || '[]')
  end

  def parsed_error_log
    JSON.parse(error_log || '[]')
  end

  # 送信結果を記録（1件分）— SQLアトミック更新でスレッドセーフ
  def record_result!(customer_id, success:, message: nil)
    # Step 1: カウンターをSQLレベルで原子的にインクリメント
    if success
      self.class.where(id: id).update_all(
        "processed_count = processed_count + 1, success_count = success_count + 1, current_customer_id = #{customer_id.to_i}"
      )
    else
      self.class.where(id: id).update_all(
        "processed_count = processed_count + 1, failure_count = failure_count + 1, current_customer_id = #{customer_id.to_i}"
      )
      # エラーログ追記（失敗時のみ、SQLite3ロック対策のリトライ付き）
      3.times do |attempt|
        begin
          reload
          errors_list = parsed_error_log
          errors_list << { customer_id: customer_id, message: message, at: Time.current.iso8601 }
          update_column(:error_log, errors_list.to_json)
          break
        rescue ActiveRecord::StatementInvalid => e
          raise unless e.message.include?('database is locked')
          sleep(rand(0.1..0.5))
        end
      end
    end

    # Step 2: 完了判定
    reload
    if processed_count >= total_count && status != 'completed'
      update_columns(status: 'completed', completed_at: Time.current)
    end
  end

  # バッチ完了
  def mark_completed!
    update!(
      status: 'completed',
      completed_at: Time.current
    )
  end

  # バッチキャンセル
  def cancel!
    update!(status: 'cancelled')
  end

  # 進捗情報（AJAX ポーリング用）
  def progress_payload
    {
      id: id,
      status: status,
      total_count: total_count,
      processed_count: processed_count,
      success_count: success_count,
      failure_count: failure_count,
      current_customer_id: current_customer_id,
      progress_percent: total_count.to_i > 0 ? ((processed_count.to_f / total_count) * 100).round(1) : 0,
      started_at: started_at&.iso8601,
      completed_at: completed_at&.iso8601
    }
  end
end
