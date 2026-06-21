class FormDetectionBatch < ApplicationRecord
  belongs_to :client, optional: true
  belongs_to :admin, optional: true

  def parsed_customer_ids
    JSON.parse(customer_ids || '[]')
  end

  def record_result!(customer_id, success:, message: nil)
    if success
      self.class.where(id: id).update_all(
        "processed_count = processed_count + 1, success_count = success_count + 1"
      )
    else
      self.class.where(id: id).update_all(
        "processed_count = processed_count + 1, error_count = error_count + 1"
      )
    end

    reload
    if processed_count >= total_count && status != 'completed'
      mark_completed!
    end
  end

  def mark_completed!
    update!(status: 'completed', completed_at: Time.current)
    
    # Create notification for form detection completion
    Notification.create_for_form_detection!(batch: self)
  end

  def cancel!
    update!(status: 'cancelled')
  end
end
