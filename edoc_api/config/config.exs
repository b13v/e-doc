# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

session_signing_salt =
  System.get_env("SESSION_SIGNING_SALT") ||
    "dev-session-signing-salt"

live_view_signing_salt =
  System.get_env("LIVE_VIEW_SIGNING_SALT") ||
    "dev-live-view-signing-salt"

jwt_secret =
  System.get_env("JWT_SECRET") ||
    Base.url_encode64(:crypto.strong_rand_bytes(64), padding: false)

parse_positive_env_int = fn key, default ->
  case System.get_env(key) do
    nil ->
      default

    value ->
      case Integer.parse(value) do
        {int_value, ""} when int_value > 0 -> int_value
        _ -> default
      end
  end
end

config :edoc_api,
  ecto_repos: [EdocApi.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  session_signing_salt: session_signing_salt

# Configures the endpoint
config :edoc_api, EdocApiWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Phoenix.Endpoint.Cowboy2Adapter,
  render_errors: [
    formats: [json: EdocApiWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: EdocApi.PubSub,
  live_view: [signing_salt: live_view_signing_salt]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally in a temporary directory. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :edoc_api, EdocApi.Mailer,
  adapter: Swoosh.Adapters.Local,
  # Keep emails in memory for /dev/mailbox
  persist: true

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :phoenix, :filter_parameters, [
  "password",
  "password_confirmation",
  "password_hash",
  "token",
  "access_token",
  "refresh_token",
  "authorization",
  "secret",
  "jwt",
  "csrf"
]

# Allow PDF MIME type
config :phoenix, :format_encoders, pdf: EdocApiWeb.PDFEncoder

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# Configures authentication
config :edoc_api, EdocApi.Auth,
  jwt_secret: jwt_secret,
  access_ttl_seconds: parse_positive_env_int.("JWT_ACCESS_TTL_SECONDS", 15 * 60),
  refresh_ttl_seconds: parse_positive_env_int.("JWT_REFRESH_TTL_SECONDS", 30 * 24 * 60 * 60)
