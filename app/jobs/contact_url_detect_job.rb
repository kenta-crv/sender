class ContactUrlDetectJob < ApplicationJob
  queue_as :form_submission
  retry_on StandardError, attempts: 0

  # 一括でお問い合わせフォームURLを自動検出
  # customer_ids: 検出対象の顧客IDの配列
  def perform(customer_ids)
    Rails.logger.info("[ContactUrlDetectJob] 開始: #{customer_ids.size}件")

    detector = ContactUrlDetector.new(debug: true, headless: true)
    detected_count = 0
    failed_count = 0

    customer_ids.each do |customer_id|
      customer = Customer.find_by(id: customer_id)
      next unless customer
      next if customer.contact_url.present?
      next if customer.url.blank?

      begin
        result = detector.detect(customer)

        if result[:status] == 'detected'
          customer.update_column(:contact_url, result[:contact_url])
          detected_count += 1
          Rails.logger.info("[ContactUrlDetectJob] 検出成功: #{customer.company} → #{result[:contact_url]}")
        else
          failed_count += 1
          Rails.logger.info("[ContactUrlDetectJob] 検出失敗: #{customer.company} - #{result[:message]}")
        end
      rescue StandardError => e
        failed_count += 1
        Rails.logger.error("[ContactUrlDetectJob] エラー: #{customer.company} - #{e.message}")
      end

      # サーバー負荷軽減のため間隔を空ける
      sleep 2
    end

    Rails.logger.info("[ContactUrlDetectJob] 完了: 検出成功=#{detected_count}, 失敗=#{failed_count}")
  end
end
