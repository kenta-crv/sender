class Submission < ApplicationRecord
    has_many :form_submission_batches, dependent: :destroy
    belongs_to :client, optional: true
end
