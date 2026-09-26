class AddStatusTextsToDialScripts < ActiveRecord::Migration[6.1]
  def change
    add_column :dial_scripts, :status_texts, :text
  end
end
