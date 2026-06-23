class AddFailureCountToFormDetectionBatches < ActiveRecord::Migration[6.1]
  def change
    add_column :form_detection_batches, :failure_count, :integer, default: 0
  end
end