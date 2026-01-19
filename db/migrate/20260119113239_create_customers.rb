class CreateCustomers < ActiveRecord::Migration[6.1]
  def change
    create_table :customers do |t|
      t.string :company #会社名
      t.string :name #代表者
      t.string :tel #電話番号1
      t.string :address #住所
      t.string :mobile #携帯番号
      t.string :industry #業種
      t.string :email #メール
      t.string :url #URL
      t.string :business #
      t.string :genre #
      t.string :contact_form 
      t.string :fobbiden
      t.string :remarks #履歴
      t.timestamps
    end
  end
end
