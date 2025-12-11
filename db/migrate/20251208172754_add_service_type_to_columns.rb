class AddServiceTypeToColumns < ActiveRecord::Migration[6.1]
  def change
    add_column :columns, :service_type, :string, null: false, default: 'cargo' 
    # 💡 既存レコードは軽貨物なのでデフォルト値を 'cargo' に設定し、NOT NULL制約をつけます。
    add_index :columns, :service_type  
  end
end
