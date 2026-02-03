class AddContactUrlToCustomers < ActiveRecord::Migration[6.1]
  def change
    unless column_exists?(:customers, :contact_url)
      add_column :customers, :contact_url, :string
    end
  end
end
