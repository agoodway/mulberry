import Config

# Test-specific configuration

# In tests, we mock all DataForSEO API calls, so credentials are not needed
# The TaskManager will use mocked Client responses
config :mulberry, :dataforseo,
  username: "test_user",
  password: "test_pass"
