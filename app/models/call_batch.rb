class CallBatch < ApplicationRecord
  belongs_to :worker, optional: true
  has_many :calls, dependent: :nullify

  def parsed_customer_ids
    JSON.parse(customer_ids || '[]')
  end

  def parsed_error_log
    JSON.parse(error_log || '[]')
  end

  # 発信結果を記録（1件分）— SQLアトミック更新でスレッドセーフ
  def record_result!(customer_id, success:, transferred: false, message: nil)
    counters = "processed_count = processed_count + 1"
    counters += ", success_count = success_count + 1" if success
    counters += ", failure_count = failure_count + 1" unless success
    counters += ", transferred_count = transferred_count + 1" if transferred

    self.class.where(id: id).update_all(counters)

    # エラーログ追記（失敗時のみ、SQLite3ロック対策のリトライ付き）
    unless success
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

    # 完了判定
    reload
    if processed_count >= total_count && status != 'completed'
      update_columns(status: 'completed', completed_at: Time.current)
    end
  end

  def pause!
    update!(status: 'paused') if status == 'processing'
  end

  def resume!
    update!(status: 'processing') if status == 'paused'
  end

  def cancel!
    update!(status: 'cancelled')
  end

  # 未処理の顧客IDを取得
  def unprocessed_customer_ids
    all_ids = parsed_customer_ids
    processed = Call.where(call_type: 'auto_phone')
                    .where(customer_id: all_ids)
                    .where(call_batch_id: id)
                    .pluck(:customer_id)
                    .uniq
    all_ids - processed
  end

  # 進捗情報（AJAXポーリング用）
  def progress_payload
    {
      id: id,
      status: status,
      total_count: total_count,
      processed_count: processed_count,
      success_count: success_count,
      failure_count: failure_count,
      transferred_count: transferred_count,
      progress_percent: total_count.to_i > 0 ? ((processed_count.to_f / total_count) * 100).round(1) : 0,
      started_at: started_at&.iso8601,
      completed_at: completed_at&.iso8601
    }
  end
end
