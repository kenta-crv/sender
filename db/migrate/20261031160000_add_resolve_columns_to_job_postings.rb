class AddResolveColumnsToJobPostings < ActiveRecord::Migration[6.1]
  def change
    add_column :job_postings, :official_name, :string
    add_column :job_postings, :headquarters_address, :string
    add_column :job_postings, :official_url, :text
  end
end
