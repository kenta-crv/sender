class FormDetectionBatch < ApplicationRecord
  belongs_to :client, optional: true
  belongs_to :admin, optional: true

  def parsed_customer_ids
    JSON.parse(customer_ids || '[]')
  end

def record_result!(customer_id, success:, message: nil)
  if success
    self.class.where(id: id).update_all(
      "processed_count = COALESCE(processed_count, 0) + 1, success_count = COALESCE(success_count, 0) + 1"
    )
  else
    self.class.where(id: id).update_all(
      "processed_count = COALESCE(processed_count, 0) + 1, failure_count = COALESCE(failure_count, 0) + 1"
    )
  end

  reload

  if processed_count.to_i >= total_count.to_i && status != 'completed'  # ← to_i 追加
    mark_completed!
  end
end

  def mark_completed!
    update!(status: 'completed', completed_at: Time.current)
    Notification.create_for_form_detection!(batch: self)
  end

  def cancel!
    update!(status: 'cancelled')
  end
end