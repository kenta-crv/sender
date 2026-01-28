class CreateContracts < ActiveRecord::Migration[6.1]
  def change
    create_table :contracts do |t|
      t.string :company #会社名
      t.string :name #担当者
      t.string :tel #電話番号
      t.string :email #メールアドレス
      t.string :address #所在地
      t.string :url #URL
      t.string :service #サービス
      t.string :period #導入時期
      t.string :message #備考
      t.timestamps
    end
  end
end
