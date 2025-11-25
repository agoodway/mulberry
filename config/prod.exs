import Config

# Production-specific configuration

# In production, always use environment variables for security
# Never commit actual credentials to version control
config :mulberry, :dataforseo,
  username: System.get_env("DATAFORSEO_USERNAME"),
  password: System.get_env("DATAFORSEO_PASSWORD")
