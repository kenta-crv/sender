class AddServiceTypeToColumns < ActiveRecord::Migration[6.1]
  def change
    add_column :columns, :genre, :string
  end
end
