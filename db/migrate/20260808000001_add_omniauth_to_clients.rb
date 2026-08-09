# frozen_string_literal: true

class AddOmniauthToClients < ActiveRecord::Migration[6.1]
  def change
    add_column :clients, :provider, :string
    add_column :clients, :uid, :string
    add_index :clients, [:provider, :uid], unique: true
  end
end
