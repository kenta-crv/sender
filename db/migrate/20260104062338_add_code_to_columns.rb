class AddCodeToColumns < ActiveRecord::Migration[6.1]
  def change
    add_column :columns, :code, :string
    add_index :columns, :code, unique: true
  end
end
