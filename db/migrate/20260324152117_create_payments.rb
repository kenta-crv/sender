class CreatePayments < ActiveRecord::Migration[6.1]
  def change
    create_table :payments do |t|
      t.references :client, null: false, foreign_key: true
      t.references :campaign, null: false, foreign_key: true
      t.integer :amount, null: false
      t.string :payjp_charge_id, null: false
      t.string :status, null: false, default: "pending"
      t.text :description
      t.timestamps
    end

    add_index :payments, :status
    add_index :payments, :payjp_charge_id
  end
end
