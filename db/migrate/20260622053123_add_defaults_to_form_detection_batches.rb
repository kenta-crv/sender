class AddDefaultsToFormDetectionBatches < ActiveRecord::Migration[6.1]
  def change
    change_column_default :form_detection_batches, :success_count, from: nil, to: 0
    change_column_default :form_detection_batches, :processed_count, from: nil, to: 0
  end
end