# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
import Config

# DataForSEO API Configuration
# Get your credentials from https://app.dataforseo.com/api-access
config :mulberry, :dataforseo,
  username: System.get_env("DATAFORSEO_USERNAME"),
  password: System.get_env("DATAFORSEO_PASSWORD")

# Import environment specific config files
# These will override the configuration defined above.
if File.exists?("config/#{config_env()}.exs") do
  import_config "#{config_env()}.exs"
end
