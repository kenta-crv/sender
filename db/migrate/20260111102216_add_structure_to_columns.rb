class AddStructureToColumns < ActiveRecord::Migration[6.1]
  def change
    add_column :columns, :article_type, :string, null: false, default: "cluster"
    add_column :columns, :parent_id, :integer
    add_column :columns, :cluster_limit, :integer

    add_index :columns, :article_type
    add_index :columns, :parent_id
  end
end
