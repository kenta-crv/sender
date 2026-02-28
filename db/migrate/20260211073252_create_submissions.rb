class CreateSubmissions < ActiveRecord::Migration[6.1]
  def change
    create_table :submissions do |t|
      t.string :headline #案件名
      t.string :company #会社名
      t.string :person #担当者
      t.string :person_kana #タントウシャ
      t.string :tel #電話番号
      t.string :fax #FAX番号
      t.string :address #住所
      t.string :email #メールアドレス
      t.string :url #HP
      t.string :title #件名
      t.string :content #本文
      t.timestamps
    end
  end
end
