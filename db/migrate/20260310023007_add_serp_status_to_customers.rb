class AddSerpStatusToCustomers < ActiveRecord::Migration[6.1]
  def change
    add_column :customers, :serp_status, :string
  end
end
