class AddDialIntentFallback < ActiveRecord::Migration[6.1]
  def change
    add_column :calls, :unknown_streak, :integer, default: 0, null: false
    add_column :calls, :pending_faq_id, :integer

    add_column :dial_scripts, :smalltalk_text, :text
    add_column :dial_scripts, :clarify_text, :text
    add_column :dial_scripts, :clarify_alt_text, :text
    add_column :dial_scripts, :clarify_simple_text, :text
    add_column :dial_scripts, :handoff_text, :text
    add_column :dial_scripts, :callback_text, :text

    create_table :dial_unknown_utterances do |t|
      t.integer :dial_script_id
      t.integer :call_id
      t.text :transcript, null: false
      t.string :classifier_path
      t.string :fallback_key
      t.integer :streak
      t.timestamps
    end
    add_index :dial_unknown_utterances, :dial_script_id
    add_index :dial_unknown_utterances, :call_id
    add_index :dial_unknown_utterances, :created_at

    create_table :dial_faqs do |t|
      t.integer :dial_script_id, null: false
      t.string :question, null: false
      t.text :answer, null: false
      t.text :phrases
      t.text :embedding
      t.timestamps
    end
    add_index :dial_faqs, :dial_script_id

    add_column :dial_utterances, :embedding, :text
  end
end
