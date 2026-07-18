class AddRemarksToCustomers < ActiveRecord::Migration[6.1]
  def change
    add_column :customers, :remarks, :text unless column_exists?(:customers, :remarks)
  end
end
