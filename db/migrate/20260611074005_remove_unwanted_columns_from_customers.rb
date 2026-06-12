class RemoveUnwantedColumnsFromCustomers < ActiveRecord::Migration[6.1]
  def change
    remove_column :customers, :name, :string
    remove_column :customers, :mobile, :string
    remove_column :customers, :industry, :string
    remove_column :customers, :remarks, :text
    remove_column :customers, :fax, :string
  end
end
