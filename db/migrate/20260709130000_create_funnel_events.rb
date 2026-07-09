class CreateFunnelEvents < ActiveRecord::Migration[6.1]
  def change
    create_table :funnel_events do |t|
      t.string  :page,                null: false
      t.string  :event_type,          null: false
      t.integer :time_spent_seconds
      t.string  :ip
      t.text    :user_agent

      t.timestamps
    end

    add_index :funnel_events, :page
    add_index :funnel_events, :event_type
    add_index :funnel_events, :created_at
  end
end
