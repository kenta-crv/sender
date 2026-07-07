class CreateDeliveryOptOuts < ActiveRecord::Migration[6.1]
  def change
    create_table :delivery_opt_outs do |t|
      t.references :customer, null: false, foreign_key: true
      t.references :client, null: false, foreign_key: true

      t.timestamps
    end

    add_index :delivery_opt_outs, [:customer_id, :client_id], unique: true
  end
end
