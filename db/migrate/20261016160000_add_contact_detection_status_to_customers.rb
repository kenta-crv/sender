class AddContactDetectionStatusToCustomers < ActiveRecord::Migration[6.1]
  def up
    add_column :customers, :contact_detection_status, :string
    add_index :customers, :contact_detection_status

    execute <<-SQL.squish
      UPDATE customers
      SET contact_detection_status = 'not_detected', contact_url = NULL
      WHERE contact_url = 'not_detected'
    SQL

    execute <<-SQL.squish
      UPDATE customers
      SET contact_detection_status = 'mailer', contact_url = NULL
      WHERE contact_url = 'メーラー起動リンクのため検出不可'
    SQL

    execute <<-SQL.squish
      UPDATE customers
      SET contact_detection_status = 'detected'
      WHERE contact_url IS NOT NULL
        AND TRIM(contact_url) != ''
        AND contact_detection_status IS NULL
    SQL
  end

  def down
    remove_index :customers, :contact_detection_status
    remove_column :customers, :contact_detection_status
  end
end
