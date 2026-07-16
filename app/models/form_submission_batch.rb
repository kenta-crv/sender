class FormSubmissionBatch < ApplicationRecord
  belongs_to :submission, optional: true
  belongs_to :client, optional: true
  belongs_to :admin, optional: true
  has_many :click_tracking_links, dependent: :destroy

  # 成功率の分母から除外する「根本送信不可」ステータス
  UNSENDABLE_RATE_STATUSES = [
    'フォーム未検出',
    'アクセス失敗',
    'CAPTCHA NG',
    '営業禁止',
    'NG対象',
    'not_detected'
  ].freeze

  scope :completed_batches, -> { where(status: 'completed') }

  def parsed_customer_ids
    JSON.parse(customer_ids || '[]')
  end

  def parsed_error_log
    JSON.parse(error_log || '[]')
  end

  # 完了バッチのみを対象に、送信不可を除いた成功率集計
  # Rate = 成功 / (成功 + 送信可能だった失敗)
  def rate_stats
    unless status == 'completed'
      return {
        eligible: false,
        success_count: 0,
        failure_count: 0,
        total_count: 0,
        excluded_count: 0,
        rate: 0.0
      }
    end

    excluded = unsendable_failure_count
    countable_failure = [failure_count.to_i - excluded, 0].max
    success = success_count.to_i
    total = success + countable_failure
    rate = total.positive? ? ((success.to_f / total) * 100).round(1) : 0.0

    {
      eligible: true,
      success_count: success,
      failure_count: countable_failure,
      total_count: total,
      excluded_count: excluded,
      rate: rate
    }
  end

  def self.aggregate_rate_stats(relation)
    totals = {
      success_count: 0,
      failure_count: 0,
      total_count: 0,
      excluded_count: 0
    }

    relation.completed_batches.find_each do |batch|
      stats = batch.rate_stats
      totals[:success_count] += stats[:success_count]
      totals[:failure_count] += stats[:failure_count]
      totals[:total_count] += stats[:total_count]
      totals[:excluded_count] += stats[:excluded_count]
    end

    total = totals[:total_count]
    totals.merge(
      rate: total.positive? ? ((totals[:success_count].to_f / total) * 100).round(1) : 0.0
    )
  end

  def unsendable_failure_count
    parsed_error_log.count do |entry|
      message =
        case entry
        when Hash
          (entry['message'] || entry[:message]).to_s
        else
          entry.to_s
        end
      unsendable_failure_message?(message)
    end
  rescue JSON::ParserError
    0
  end

  def unsendable_failure_message?(message)
    UNSENDABLE_RATE_STATUSES.any? do |status|
      message == status || message.start_with?("#{status}:")
    end
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
    Notification.create_for_form_submission!(batch: self)
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