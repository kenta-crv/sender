class AddSerpErrorAtToCustomers < ActiveRecord::Migration[6.1]
  def change
    add_column :customers, :serp_error_at, :datetime
  end
end