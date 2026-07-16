class CustomerDuplicateCleanupJob < ApplicationJob
  queue_as :form_submission_admin

  retry_on StandardError, attempts: 0

  def perform(attribute, client_signed_in, admin_signed_in, client_id = nil)
    scope = Customer.duplicate_cleanup_scope(
      client_signed_in: client_signed_in,
      admin_signed_in: admin_signed_in,
      client_id: client_id
    )

    total_deleted = Customer.cleanup_duplicates!(attribute: attribute, scope: scope)

    Notification.create_for_duplicate_cleanup!(
      attribute: attribute,
      total_deleted: total_deleted,
      client_id: client_id
    )
  rescue StandardError => e
    Rails.logger.error("[CustomerDuplicateCleanupJob] #{e.class}: #{e.message}\n#{e.backtrace&.first(15)&.join("\n")}")

    Notification.create_for_duplicate_cleanup!(
      attribute: attribute,
      total_deleted: 0,
      client_id: client_id,
      fatal_error: e.message
    )
  end
end
