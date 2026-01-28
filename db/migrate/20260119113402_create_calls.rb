class CreateCalls < ActiveRecord::Migration[6.1]
  def change
    create_table :calls do |t|
      t.string :status #ステータス
      t.string :comment #コメント
      t.references :customer, foreign_key: true
      t.timestamps
    end
  end
end
