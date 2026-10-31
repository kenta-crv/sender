class CreateJobPostings < ActiveRecord::Migration[6.1]
  def change
    create_table :job_postings do |t|
      t.string :source, null: false, default: "kyujinbox"
      t.string :company_raw
      t.string :company_clean
      t.string :title
      t.string :area
      t.string :employ_type
      t.text :posting_url
      t.string :job_key, null: false
      t.datetime :first_seen_at
      t.datetime :last_seen_at
      t.string :status, null: false, default: "new"
      t.string :skip_reason
      t.string :corporate_number
      t.integer :customer_id

      t.timestamps
    end

    add_index :job_postings, :job_key, unique: true
    add_index :job_postings, :company_clean
    add_index :job_postings, :last_seen_at
    add_index :job_postings, :status
    add_index :job_postings, :customer_id
  end
end
