ENV['BUNDLE_GEMFILE'] ||= File.expand_path('../Gemfile', __dir__)

# VPS本番も含め .env を読む（毎回 source しなくてよい）
env_path = File.expand_path('../.env', __dir__)
if File.exist?(env_path)
  File.foreach(env_path) do |line|
    line = line.strip
    next if line.empty? || line.start_with?('#')

    key, value = line.split('=', 2)
    next if key.nil? || key.empty? || value.nil?

    value = value.strip.delete_prefix('"').delete_suffix('"').delete_prefix("'").delete_suffix("'")
    ENV[key] ||= value
  end
end

require 'logger'
require 'bundler/setup' # Set up gems listed in the Gemfile.
# bootsnap disabled: incompatible with non-ASCII paths (OneDrive Japanese directory)
# require 'bootsnap/setup'
