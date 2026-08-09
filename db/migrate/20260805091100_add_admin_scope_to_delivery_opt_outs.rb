class AddAdminScopeToDeliveryOptOuts < ActiveRecord::Migration[6.1]
  def change
    change_column_null :delivery_opt_outs, :client_id, true
    add_reference :delivery_opt_outs, :admin, foreign_key: true

    add_index :delivery_opt_outs, [:customer_id, :admin_id], unique: true
  end
end
