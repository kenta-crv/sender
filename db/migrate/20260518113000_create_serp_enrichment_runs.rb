class CreateSerpEnrichmentRuns < ActiveRecord::Migration[6.1]
  def change
    create_table :serp_enrichment_runs do |t|
      t.string :run_id, null: false
      t.string :jid
      t.string :status, null: false, default: "queued"
      t.string :industry
      t.integer :limit, null: false, default: 0
      t.integer :target_count, null: false, default: 0
      t.integer :serp_total, null: false, default: 0
      t.integer :serp_completed, null: false, default: 0
      t.integer :web_total, null: false, default: 0
      t.integer :web_completed, null: false, default: 0
      t.datetime :started_at
      t.datetime :finished_at
      t.text :error_message
      t.text :summary_json

      t.timestamps
    end

    add_index :serp_enrichment_runs, :run_id, unique: true
    add_index :serp_enrichment_runs, :jid
    add_index :serp_enrichment_runs, :status
    add_index :serp_enrichment_runs, :created_at

    create_table :serp_enrichment_run_targets do |t|
      t.references :serp_enrichment_run, null: false, foreign_key: true, index: { name: "index_serp_targets_on_run_id" }
      t.integer :customer_id, null: false
      t.integer :position, null: false, default: 0
      t.string :company
      t.string :before_serp_status
      t.string :before_tel
      t.text :before_address
      t.string :before_url
      t.string :before_contact_url
      t.string :after_serp_status
      t.string :after_tel
      t.text :after_address
      t.string :after_url
      t.string :after_contact_url
      t.string :result_status, null: false, default: "pending"
      t.integer :candidate_count, null: false, default: 0
      t.string :selected_url
      t.text :update_keys
      t.text :error_message

      t.timestamps
    end

    add_index :serp_enrichment_run_targets, :customer_id
    add_index :serp_enrichment_run_targets, :result_status
    add_index :serp_enrichment_run_targets,
              [:serp_enrichment_run_id, :customer_id],
              name: "index_serp_targets_on_run_and_customer"
  end
end
