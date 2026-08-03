class ContactUrlDetectJob < ApplicationJob
  queue_as :form_detection_standard
  retry_on StandardError, attempts: 0

  # customer_id が nil のときはバッチ内顧客を子ジョブとしてファンアウトする（HTTP 内の大量 enqueue による 504 回避）
  def perform(customer_id, batch_id = nil)
    if customer_id.nil?
      enqueue_batch(batch_id)
      return
    end

    batch = FormDetectionBatch.find_by(id: batch_id) if batch_id

    customer = Customer.find_by(id: customer_id)
    unless customer
      batch&.record_result!(customer_id, success: false, message: '顧客が見つかりません')
      return
    end

    if customer.contact_url.present?
      batch&.record_result!(customer_id, success: true)
      return
    end

    if customer.url.blank?
      batch&.record_result!(customer_id, success: false, message: 'URLが未設定です')
      return
    end

    Rails.logger.info("[ContactUrlDetectJob] 開始: #{customer.company} (ID: #{customer_id})")

    detector = nil
    success = false
    begin
      detector = ContactUrlDetector.new(debug: true, headless: true)
      result = detector.detect(customer)

      if result[:status] == 'detected'
        customer.update_column(:contact_url, result[:contact_url])
        Rails.logger.info("[ContactUrlDetectJob] 検出成功: #{customer.company} → #{result[:contact_url]}")
        success = true
      else
        customer.update_column(:contact_url, 'not_detected')
        Rails.logger.info("[ContactUrlDetectJob] 検出失敗: #{customer.company} - #{result[:message]}")
      end
    rescue StandardError => e
      customer.update_column(:contact_url, 'not_detected') rescue nil
      Rails.logger.error("[ContactUrlDetectJob] エラー: #{customer.company} - #{e.message}")
    ensure
      detector&.teardown_driver rescue nil
    end

    batch&.record_result!(customer_id, success: success)
  end

  private

  def enqueue_batch(batch_id)
    batch = FormDetectionBatch.find_by(id: batch_id)
    return unless batch
    return if batch.status == 'cancelled'

    customer_ids = batch.parsed_customer_ids
    return if customer_ids.empty?

    admin = batch.admin_id.present?
    batch_size = 100
    slice_count = (customer_ids.size.to_f / batch_size).ceil

    Rails.logger.info(
      "[ContactUrlDetectJob] ファンアウト開始: batch_id=#{batch_id}, count=#{customer_ids.size}"
    )

    customer_ids.each_slice(batch_size).with_index do |slice, index|
      slice.each do |cid|
        PlanPriorityQueue.enqueue_contact_detect(
          cid,
          batch.id,
          client: batch.client,
          admin: admin
        )
      end
      sleep(0.1) if index < slice_count - 1
    end
  end
end
