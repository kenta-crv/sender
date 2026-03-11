class AddManualToSubmissions < ActiveRecord::Migration[6.1]
  def change
    add_column :submissions, :manual, :boolean
  end
end
