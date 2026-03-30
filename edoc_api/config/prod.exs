import Config

# Configures Swoosh API Client
config :swoosh, api_client: Swoosh.ApiClient.Finch, finch_name: EdocApi.Finch

# Disable Swoosh Local Memory Storage
config :swoosh, local: false

# Do not print debug messages in production
config :logger, level: :info

# Secure cookies in production
config :edoc_api, :secure_cookies, true

# Configure Oban for background jobs in production
config :edoc_api, Oban,
  repo: EdocApi.Repo,
  queues: [default: 10, pdf_generation: 5],
  plugins: [
    Oban.Plugins.Pruner,
    Oban.Plugins.Lifeline
  ]

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
