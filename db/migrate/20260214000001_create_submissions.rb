class CreateSubmissions < ActiveRecord::Migration[6.1]
  def change
    create_table :submissions do |t|
      t.string :headline
      t.string :company
      t.string :person
      t.string :person_kana
      t.string :tel
      t.string :fax
      t.string :address
      t.string :email
      t.string :url
      t.string :title
      t.text :content

      t.timestamps
    end
  end
end
