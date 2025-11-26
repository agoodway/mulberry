# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
import Config

# DataForSEO API Configuration
# Get your credentials from https://app.dataforseo.com/api-access
config :mulberry, :dataforseo,
  username: System.get_env("DATAFORSEO_USERNAME"),
  password: System.get_env("DATAFORSEO_PASSWORD")

# Business Listing Unique ID Configuration
# Controls how unique identifiers are generated for business listings
config :mulberry, DataForSEO.Schemas.BusinessListing,
  # ID generation strategy: :cid (default), :place_id, :composite_hash, or :custom
  id_strategy: :cid,
  # Fields to use for composite_hash strategy
  composite_fields: [:cid, :place_id],
  # Optional prefix for generated IDs (e.g., "bl_" results in "bl_12345")
  id_prefix: nil

# Import environment specific config files
# These will override the configuration defined above.
if File.exists?("config/#{config_env()}.exs") do
  import_config "#{config_env()}.exs"
end
