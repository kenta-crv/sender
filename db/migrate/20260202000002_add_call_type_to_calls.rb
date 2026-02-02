class AddCallTypeToCalls < ActiveRecord::Migration[6.1]
  def up
    add_column :calls, :call_type, :string, default: 'phone'

    # 既存のフォーム送信レコードをバックフィル
    execute <<-SQL
      UPDATE calls SET call_type = 'form' WHERE comment LIKE '%フォーム送信%'
    SQL
  end

  def down
    remove_column :calls, :call_type
  end
end
