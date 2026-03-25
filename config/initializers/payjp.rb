Payjp.api_key = Rails.application.credentials.dig(:payjp, :secret_key) || ENV['PAYJP_SECRET_KEY']
