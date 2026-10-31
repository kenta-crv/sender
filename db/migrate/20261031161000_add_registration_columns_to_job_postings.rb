class AddRegistrationColumnsToJobPostings < ActiveRecord::Migration[6.1]
  def change
    add_column :job_postings, :registration_kind, :string
    add_column :job_postings, :registered_at, :datetime
    add_column :job_postings, :serp_filled_at, :datetime
  end
end
