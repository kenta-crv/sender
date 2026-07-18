class AddCompanyInfoColumnsToCustomers < ActiveRecord::Migration[6.1]
  def change
    add_column :customers, :capital, :string unless column_exists?(:customers, :capital)
    add_column :customers, :establish, :string unless column_exists?(:customers, :establish)
    add_column :customers, :ceo, :string unless column_exists?(:customers, :ceo)
    add_column :customers, :people, :string unless column_exists?(:customers, :people)
  end
end
