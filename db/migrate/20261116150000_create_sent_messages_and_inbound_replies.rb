class CreateSentMessagesAndInboundReplies < ActiveRecord::Migration[6.1]
  def change
    # フォーム送信に成功した記録（返信との照合用）
    create_table :sent_messages do |t|
      t.integer :customer_id
      t.integer :form_submission_batch_id
      t.integer :client_id
      t.string :domain
      t.text :body
      t.datetime :sent_at, null: false
      t.timestamps
    end
    add_index :sent_messages, [:domain, :sent_at]
    add_index :sent_messages, :customer_id

    # 受信箱から取り込んだメール
    create_table :inbound_replies do |t|
      t.integer :imap_uid, null: false
      t.integer :imap_uidvalidity, null: false
      t.string :message_id
      t.string :from_address
      t.string :from_domain
      t.string :subject
      t.text :body
      t.datetime :received_at
      t.string :classification, null: false, default: 'unknown' # auto / human / unknown
      t.string :manual_classification
      t.integer :score, default: 0
      t.text :reasons
      t.integer :sent_message_id
      t.integer :customer_id
      t.timestamps
    end
    add_index :inbound_replies, [:imap_uidvalidity, :imap_uid], unique: true
    add_index :inbound_replies, :classification
    add_index :inbound_replies, :received_at
  end
end
