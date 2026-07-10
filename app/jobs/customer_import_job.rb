class CustomerImportJob < ApplicationJob
  queue_as :form_submission_admin

  retry_on StandardError, attempts: 0

  def perform(file_path, overwrite_blank = false, client_id = nil)
    result = CustomerImportService.new(
      overwrite_blank: overwrite_blank,
      client_id: client_id
    ).call(file_path)

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

    raise
  ensure
    File.delete(file_path) if file_path.present? && File.exist?(file_path)
  end
end
