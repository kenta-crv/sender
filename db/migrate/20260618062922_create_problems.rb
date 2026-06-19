class CreateProblems < ActiveRecord::Migration[6.1]
  def change
    create_table :problems do |t|
      t.string :company
      t.string :email
      t.string :body
      t.string :photo
      t.timestamps
    end
  end
end
