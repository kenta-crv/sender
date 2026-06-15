require_relative 'boot'

require 'rails/all'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Smart
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 5.2
    config.active_job.queue_adapter = :sidekiq
    config.autoload_paths << Rails.root.join('app/lib')
    config.autoload_paths << Rails.root.join('app/uploaders')
    config.eager_load_paths << Rails.root.join('app/uploaders')    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration can go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded after loading
    # the framework and any gems in your application.

    # ---------------------------------------------------------
    # タイムゾーン設定（日本時間への変更と9時間差の解消）
    # ---------------------------------------------------------
    config.time_zone = 'Tokyo'
    config.active_record.default_timezone = :local

    config.action_mailer.delivery_method = :smtp
    config.action_mailer.smtp_settings = {
    address: 'smtp.lolipop.jp',
    domain: 'ri-plus.jp',
    port: 587,
    user_name: 'info@ri-plus.jp',
    password: ENV['EMAIL_PASSWORD'],
    authentication: 'plain',
    enable_starttls_auto: true
    }
  end
end