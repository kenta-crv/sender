class AddUnsubscribeTokenToCustomers < ActiveRecord::Migration[6.1]
  def change
    add_column :customers, :unsubscribe_token, :string
    add_index :customers, :unsubscribe_token, unique: true
  end
end
