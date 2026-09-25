class AddAdminToFormDetectionBatches < ActiveRecord::Migration[6.1]
  def change
    add_reference :form_detection_batches, :admin, foreign_key: true
  end
end
