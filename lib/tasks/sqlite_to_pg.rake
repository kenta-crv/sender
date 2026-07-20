# frozen_string_literal: true

# 使い方（本番サーバー）:
#   sudo -u postgres psql -c "ALTER USER okurite WITH SUPERUSER;"
#   RAILS_ENV=production DISABLE_SPRING=1 bundle exec rake db:sqlite_to_pg
#   sudo -u postgres psql -c "ALTER USER okurite WITH NOSUPERUSER;"
#
# SQLite のパスは ENV['SQLITE_PATH'] で上書き可（既定: db/development.sqlite3）
# バッチサイズは ENV['SQLITE_TO_PG_BATCH']（既定: 500）

namespace :db do
  desc "Copy data from SQLite into current DB (PostgreSQL), preserving IDs"
  task sqlite_to_pg: :environment do
    sqlite_path = ENV.fetch("SQLITE_PATH", Rails.root.join("db/development.sqlite3").to_s)
    raise "SQLite file not found: #{sqlite_path}" unless File.exist?(sqlite_path)

    batch_size = ENV.fetch("SQLITE_TO_PG_BATCH", "500").to_i
    batch_size = 500 if batch_size <= 0

    # ActiveRecord は匿名クラスへの establish_connection を拒否するため名前付きにする
    unless defined?(SqliteImportRecord)
      Object.const_set(:SqliteImportRecord, Class.new(ActiveRecord::Base) do
        self.abstract_class = true
      end)
    end

    SqliteImportRecord.establish_connection(
      adapter: "sqlite3",
      database: sqlite_path,
      pool: 5,
      timeout: 5000
    )

    skip = %w[schema_migrations ar_internal_metadata]
    tables = ActiveRecord::Base.connection.tables.sort - skip
    conn = ActiveRecord::Base.connection

    begin
      conn.execute("SET session_replication_role = replica")
    rescue ActiveRecord::StatementInvalid => e
      raise "Need SUPERUSER (or REPLICATION) for import: #{e.message}"
    end

    tables.each do |table|
      next unless SqliteImportRecord.connection.table_exists?(table)

      pg_columns = conn.columns(table).index_by(&:name)
      cols = SqliteImportRecord.connection.columns(table).map(&:name) & pg_columns.keys
      next if cols.empty?

      sql_cols = cols.map { |c| %("#{c}") }.join(", ")
      rows = SqliteImportRecord.connection.exec_query("SELECT #{sql_cols} FROM #{table}")
      next if rows.rows.empty?

      quoted_cols = cols.map { |c| conn.quote_column_name(c) }.join(", ")
      boolean_cast = ActiveModel::Type::Boolean.new
      inserted = 0

      rows.rows.each_slice(batch_size) do |slice|
        values_sql = slice.map do |row|
          "(" + row.each_with_index.map { |v, i|
            col = pg_columns[cols[i]]
            v = boolean_cast.cast(v) if col&.type == :boolean
            conn.quote(v)
          }.join(", ") + ")"
        end.join(", ")
        conn.execute("INSERT INTO #{table} (#{quoted_cols}) VALUES #{values_sql}")
        inserted += slice.size
      end

      conn.reset_pk_sequence!(table) if cols.include?("id")
      puts "#{table}: #{inserted}"
    end

    conn.execute("SET session_replication_role = DEFAULT")
    puts "DONE"

    %w[admins clients customers calls subscriptions workers].each do |t|
      next unless SqliteImportRecord.connection.table_exists?(t) && conn.table_exists?(t)

      s = SqliteImportRecord.connection.select_value("SELECT COUNT(*) FROM #{t}")
      p = conn.select_value("SELECT COUNT(*) FROM #{t}")
      puts "compare #{t}: sqlite=#{s} pg=#{p}"
    end
  end
end
