import Config

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: EdocApi.Finch

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :info

# Secure cookies in production
config :edoc_api, :secure_cookies, true

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
