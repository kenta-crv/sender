class FormSendJob < ApplicationJob
  queue_as :form_submission
  retry_on StandardError, attempts: 0

  # 自己チェイン方式で1件ずつ順番に処理
  # batch_id: FormSubmissionBatch の ID
  # index: customer_ids 配列内の現在のインデックス
  def perform(batch_id, index = 0)
    batch = FormSubmissionBatch.find_by(id: batch_id)
    return unless batch
    return if batch.status == 'cancelled'

    ids = batch.parsed_customer_ids
    return batch.mark_completed! if index >= ids.size

    # 初回実行時にステータスを更新
    if index == 0
      batch.update!(status: 'processing', started_at: Time.current)
    end

    customer_id = ids[index]
    customer = Customer.find_by(id: customer_id)

    unless customer
      batch.record_result!(customer_id, success: false, message: '顧客が見つかりません')
      chain_next(batch_id, index)
      return
    end

    # FormSender で送信実行（Sidekiq 環境ではヘッドレスモード）
    begin
      sender = FormSender.new(debug: true, headless: true, save_to_db: true)
      result = sender.send_to_customer(customer)

      success = result[:status] == '自動送信成功'
      batch.record_result!(
        customer_id,
        success: success,
        message: "#{result[:status]}: #{result[:message]}"
      )
    rescue StandardError => e
      Rails.logger.error("[FormSendJob] customer_id=#{customer_id} エラー: #{e.message}")
      batch.record_result!(customer_id, success: false, message: e.message)
    end

    # 次の顧客へチェイン
    chain_next(batch_id, index)
  end

  private

  def chain_next(batch_id, current_index)
    batch = FormSubmissionBatch.find_by(id: batch_id)
    return unless batch
    return if batch.status == 'cancelled'

    next_index = current_index + 1
    ids = batch.parsed_customer_ids

    if next_index >= ids.size
      batch.mark_completed!
    else
      FormSendJob.perform_later(batch_id, next_index)
    end
  end
end
