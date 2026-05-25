class CreateClickLogs < ActiveRecord::Migration[6.1]
  def change
    create_table :click_logs do |t|
      t.references :click_tracking_link,
                   null: false,
                   foreign_key: true

      t.string :ip
      t.text :user_agent

      t.timestamps
    end
  end
end