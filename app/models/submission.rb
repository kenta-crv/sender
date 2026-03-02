class Submission < ApplicationRecord
    has_many :form_submission_batches, dependent: :destroy

end
