class CreateNotifications < ActiveRecord::Migration[6.1]
  def change
    create_table :notifications do |t|
      t.string :type
      t.string :status
      t.integer :total_count
      t.integer :success_count
      t.integer :error_count
      t.integer :client_id
      t.datetime :read_at
      t.string :notifiable_type
      t.integer :notifiable_id
      t.text :message

      t.timestamps
    end

    add_index :notifications, :client_id
    add_index :notifications, :read_at
    add_index :notifications, :notifiable_type
    add_index :notifications, :notifiable_id
    add_index :notifications, [:notifiable_type, :notifiable_id]
    add_index :notifications, :created_at
  end
end
