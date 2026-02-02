class FormSubmissionBatch < ApplicationRecord
  # customer_ids と error_log は JSON テキストとして保存
  def parsed_customer_ids
    JSON.parse(customer_ids || '[]')
  end

  def parsed_error_log
    JSON.parse(error_log || '[]')
  end

  # 送信結果を記録（1件分）
  def record_result!(customer_id, success:, message: nil)
    self.processed_count += 1
    if success
      self.success_count += 1
    else
      self.failure_count += 1
      errors_list = parsed_error_log
      errors_list << { customer_id: customer_id, message: message, at: Time.current.iso8601 }
      self.error_log = errors_list.to_json
    end
    self.current_customer_id = customer_id
    save!
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
