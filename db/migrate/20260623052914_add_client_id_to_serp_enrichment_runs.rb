class AddClientIdToSerpEnrichmentRuns < ActiveRecord::Migration[6.1]
  def change
    add_column :serp_enrichment_runs, :client_id, :integer
  end
end
