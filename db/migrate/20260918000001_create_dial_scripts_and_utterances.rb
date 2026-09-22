class CreateDialScriptsAndUtterances < ActiveRecord::Migration[6.1]
  def change
    create_table :dial_scripts do |t|
      t.string :name, null: false
      t.text :css
      t.text :greeting_text
      t.text :purpose_text
      t.text :wait_text
      t.text :absent_text
      t.text :rejection_text
      t.text :no_human_text
      t.text :repeat_text
      t.text :closing_text
      t.timestamps
    end

    create_table :dial_utterances do |t|
      t.references :dial_script, null: false, foreign_key: true
      t.string :phrase, null: false
      t.string :script_key, null: false
      t.timestamps
    end
    add_index :dial_utterances, [:dial_script_id, :phrase]
  end
end
