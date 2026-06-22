class ContactUrlDetectJob < ApplicationJob
  queue_as :form_submission
  retry_on StandardError, attempts: 0

  def perform(customer_id, batch_id = nil)
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
end