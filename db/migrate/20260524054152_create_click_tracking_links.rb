class CreateClickTrackingLinks < ActiveRecord::Migration[6.1]
  def change
    create_table :click_tracking_links do |t|
      t.string :token, null: false

      t.references :customer, foreign_key: true
      t.references :client, foreign_key: true
      t.references :admin, foreign_key: true

      t.text :target_url

      t.integer :clicked_count,
                default: 0,
                null: false

      t.datetime :last_clicked_at

      t.timestamps
    end

    add_index :click_tracking_links,
              :token,
              unique: true
  end
end