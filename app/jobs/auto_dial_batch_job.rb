class AutoDialBatchJob < ApplicationJob
  queue_as :auto_dial

  # バッチ内の全顧客分のAutoDialJobをエンキュー
  def perform(batch_id)
    batch = CallBatch.find_by(id: batch_id)
    return unless batch&.status == 'processing'

    batch.parsed_customer_ids.each do |customer_id|
      AutoDialJob.perform_later(batch_id, customer_id)
    end
  end
end
