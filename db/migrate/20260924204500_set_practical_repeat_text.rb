class SetPracticalRepeatText < ActiveRecord::Migration[6.1]
  def up
    change_column_default :dial_scripts, :repeat_text, 'もう一度おっしゃっていただけますか。'
    execute <<~SQL.squish
      UPDATE dial_scripts
      SET repeat_text = 'もう一度おっしゃっていただけますか。'
      WHERE repeat_text IS NULL OR repeat_text = ''
    SQL
  end

  def down
    change_column_default :dial_scripts, :repeat_text, nil
  end
end
