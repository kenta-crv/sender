class AddSubmissionRefsToClickTrackingLinks < ActiveRecord::Migration[6.1]
  def change
    add_reference :click_tracking_links, :submission, foreign_key: true
    add_reference :click_tracking_links, :form_submission_batch, foreign_key: true
  end
end
