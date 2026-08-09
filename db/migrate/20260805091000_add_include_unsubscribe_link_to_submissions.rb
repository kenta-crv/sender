class AddIncludeUnsubscribeLinkToSubmissions < ActiveRecord::Migration[6.1]
  def change
    add_column :submissions, :include_unsubscribe_link, :boolean, null: false, default: true
  end
end
