source 'https://rubygems.org'
git_source(:github) { |repo| "https://github.com/#{repo}.git" }

# Rails
gem 'rails', '~> 6.1.7'

# Database
gem 'sqlite3', '~> 1.6'

# Web server
gem 'puma', '~> 3.11'

# Assets
gem 'sass-rails', '~> 5.0'
gem 'uglifier', '>= 1.3.0'
gem 'coffee-rails', '~> 4.2'
gem 'turbolinks', '~> 5'
gem 'jbuilder', '~> 2.5'
gem 'jquery-rails'
gem 'bootstrap', '~> 4.0.0'
gem 'select2-rails'
gem 'audiojs-rails'

# Performance
gem 'bootsnap', '>= 1.1.0', require: false
gem 'lograge'

# Authentication & Authorization
gem 'devise'
gem 'omniauth-twitter'

# SEO / Meta
gem 'meta-tags'
gem 'sitemap_generator'
gem 'breadcrumbs_on_rails'
gem 'friendly_id', '~> 5.5'

# File upload
gem 'carrierwave'

# Background jobs
gem 'sidekiq', '~> 5.2'
gem 'sidekiq-cron'

# Markdown / Text processing
gem 'kramdown'
gem 'rails_autolink'
gem 'haml-rails', '~> 2.0'
gem 'haml', '~> 6.0'

# Data handling / Utilities
gem 'dotenv-rails', groups: [:development, :test, :production]
gem 'faker'
gem 'roo'
gem 'active_hash'
gem 'simple_enum'
gem 'annotate'
gem 'ransack'
gem 'jp_prefecture'

# API / HTTP
gem 'httparty'
gem 'openai'
gem 'open_uri_redirections'
gem 'twilio-ruby'
gem 'google-cloud-speech'
gem 'net-imap', '~> 0.3.9'
gem 'mail', '~> 2.8'

# Pagination
gem 'kaminari'
gem 'kaminari-bootstrap', '~> 3.0.1'

# Charts
gem 'chartkick'

# Cron / Scheduling
gem 'whenever', require: false

# Development & Test
group :development, :test do
  gem 'byebug', platforms: [:mri, :mingw, :x64_mingw]
end

group :development do
  gem 'web-console', '~> 4.2'
  gem 'listen', '>= 3.0.5', '< 3.2'
  gem 'spring'
  gem 'spring-watcher-listen', '~> 2.0.0'
  gem 'pry-rails'
end

group :test do
  gem 'capybara', '>= 2.15'
  gem 'selenium-webdriver'
  gem 'chromedriver-helper'
end

# Windows only
gem 'tzinfo-data', platforms: [:mingw, :mswin, :x64_mingw, :jruby]

gem 'slim-rails'