# frozen_string_literal: true

class AddExecutionAccessFieldsToClients < ActiveRecord::Migration[6.1]
  def change
    change_table :clients, bulk: true do |t|
      t.string   :confirmation_token
      t.datetime :confirmed_at
      t.datetime :confirmation_sent_at
      t.string   :unconfirmed_email
      t.string   :registration_ip
      t.boolean  :registration_flagged, default: false, null: false
      t.string   :stripe_payment_method_id
      t.string   :card_fingerprint
    end

    add_index :clients, :confirmation_token, unique: true
    add_index :clients, :registration_ip
    add_index :clients, :card_fingerprint

    reversible do |dir|
      dir.up do
        execute <<~SQL.squish
          UPDATE clients SET confirmed_at = created_at WHERE confirmed_at IS NULL
        SQL
      end
    end
  end
end
