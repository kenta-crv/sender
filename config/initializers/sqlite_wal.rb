if defined?(ActiveRecord)
  Rails.application.config.after_initialize do
    if ActiveRecord::Base.connection.adapter_name.downcase.include?('sqlite')
      ActiveRecord::Base.connection.execute('PRAGMA journal_mode=WAL')
      ActiveRecord::Base.connection.execute('PRAGMA synchronous=NORMAL')
      ActiveRecord::Base.connection.execute('PRAGMA busy_timeout=10000')
    end
  end
end
