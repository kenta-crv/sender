class Submission < ApplicationRecord
    belongs_to :client, optional: true
    has_many :form_submission_batches, dependent: :destroy
    has_many :click_tracking_links, dependent: :destroy
end
