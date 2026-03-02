class ContactUrlDetectJob < ApplicationJob
  queue_as :form_submission
  retry_on StandardError, attempts: 0

  # 1顧客のお問い合わせフォームURLを自動検出（並列処理用: 1ジョブ=1顧客）
  def perform(customer_id)
    customer = Customer.find_by(id: customer_id)
    return unless customer
    return if customer.contact_url.present?
    return if customer.url.blank?

    Rails.logger.info("[ContactUrlDetectJob] 開始: #{customer.company} (ID: #{customer_id})")

    detector = nil
    begin
      detector = ContactUrlDetector.new(debug: true, headless: true)
      result = detector.detect(customer)

      if result[:status] == 'detected'
        customer.update_column(:contact_url, result[:contact_url])
        Rails.logger.info("[ContactUrlDetectJob] 検出成功: #{customer.company} → #{result[:contact_url]}")
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
  end
end
