class CreateKyujinboxBackfillCursors < ActiveRecord::Migration[6.1]
  def change
    create_table :kyujinbox_backfill_cursors do |t|
      t.string :start_url, null: false
      t.string :next_url
      t.integer :pages_read, null: false, default: 0
      t.boolean :finished, null: false, default: false
      t.string :stop_reason
      t.timestamps
    end
    add_index :kyujinbox_backfill_cursors, :start_url, unique: true
  end
end
