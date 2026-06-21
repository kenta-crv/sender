class FormSubmissionBatch < ApplicationRecord
  belongs_to :submission, optional: true
  belongs_to :client, optional: true
  belongs_to :admin, optional: true

  def parsed_customer_ids
    JSON.parse(customer_ids || '[]')
  end

  def parsed_error_log
    JSON.parse(error_log || '[]')
  end

  def record_result!(customer_id, success:, message: nil)
    if success
      self.class.where(id: id).update_all(
        "processed_count = processed_count + 1, success_count = success_count + 1, current_customer_id = #{customer_id.to_i}"
      )
    else
      self.class.where(id: id).update_all(
        "processed_count = processed_count + 1, failure_count = failure_count + 1, current_customer_id = #{customer_id.to_i}"
      )
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

    reload
    if processed_count >= total_count && status != 'completed'
      mark_completed!
    end
  end

  def mark_completed!
    update!(status: 'completed', completed_at: Time.current)

    # Create notification for form submission completion
    Notification.create_for_form_submission!(batch: self)

    if client.present?
      ClientMailer.form_submission_result_email(client, self).deliver_now
    elsif admin.present?
      ClientMailer.form_submission_result_email(admin, self).deliver_now
    end
  end

  def cancel!
    update!(status: 'cancelled')
  end

  def unprocessed_customer_ids
    all_ids = parsed_customer_ids
    processed = Call.where(call_type: 'form')
                    .where(customer_id: all_ids)
                    .where('created_at >= ?', created_at)
                    .pluck(:customer_id)
                    .uniq
    all_ids - processed
  end

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