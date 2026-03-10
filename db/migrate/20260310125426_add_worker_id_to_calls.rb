class AddWorkerIdToCalls < ActiveRecord::Migration[6.1]
  def change
    add_column :calls, :worker_id, :integer
  end
end
