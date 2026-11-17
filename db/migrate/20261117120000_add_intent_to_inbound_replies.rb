class AddIntentToInboundReplies < ActiveRecord::Migration[6.1]
  def change
    add_column :inbound_replies, :intent, :string       # 人の返信の中身: interest / question / decline / none
    add_column :inbound_replies, :ai_used, :boolean, default: false, null: false
  end
end
