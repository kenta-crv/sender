class CustomerImportJob < ApplicationJob
  queue_as :form_submission_admin

  retry_on StandardError, attempts: 0

  def perform(csv_content, overwrite_blank = false, client_id = nil)
    result = CustomerImportService.new(
      overwrite_blank: overwrite_blank,
      client_id: client_id
    ).call(csv_content: csv_content)

    Notification.create_for_customer_import!(
      import_count: result[:import_count],
      error_count: result[:error_count],
      error_samples: result[:error_samples],
      client_id: client_id
    )
  rescue StandardError => e
    Rails.logger.error("CUSTOMER IMPORT FATAL ERROR: #{e.message}\n#{e.backtrace.join("\n")}")

    Notification.create_for_customer_import!(
      import_count: 0,
      error_count: 0,
      error_samples: [],
      client_id: client_id,
      fatal_error: e.message
    )

    # 失敗通知はここで送るため、再raiseして通知重複を起こさない
  end
end
