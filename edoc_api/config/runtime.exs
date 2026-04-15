import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/edoc_api start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :edoc_api, EdocApiWeb.Endpoint, server: true
end

if config_env() == :prod do
  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :edoc_api, EdocApi.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "20"),
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  session_signing_salt =
    System.get_env("SESSION_SIGNING_SALT") ||
      raise """
      environment variable SESSION_SIGNING_SALT is missing.
      Set a stable, random value for production session signing.
      """

  live_view_signing_salt =
    System.get_env("LIVE_VIEW_SIGNING_SALT") ||
      raise """
      environment variable LIVE_VIEW_SIGNING_SALT is missing.
      Set a stable, random value for production LiveView signing.
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :edoc_api, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :edoc_api, EdocApiWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/plug_cowboy/Plug.Cowboy.html
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    live_view: [signing_salt: live_view_signing_salt],
    force_ssl: [hsts: true],
    secure_browser_headers: %{
      "x-content-type-options" => "nosniff",
      "x-frame-options" => "DENY",
      "referrer-policy" => "strict-origin-when-cross-origin",
      "permissions-policy" => "camera=(), microphone=(), geolocation=()",
      "content-security-policy" =>
        "default-src 'self'; img-src 'self' data:; style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline' https://cdn.tailwindcss.com; connect-src 'self'; font-src 'self' data:; object-src 'none'; frame-ancestors 'none'; form-action 'self'; base-uri 'self'"
    }

  config :edoc_api, :session_signing_salt, session_signing_salt

  trusted_proxies =
    System.get_env("TRUSTED_PROXY_IPS", "")
    |> String.split(",", trim: true)
    |> Enum.reduce([], fn value, acc ->
      value = String.trim(value)

      case :inet.parse_address(String.to_charlist(value)) do
        {:ok, ip} -> [ip | acc]
        _ -> acc
      end
    end)
    |> Enum.reverse()

  config :edoc_api, EdocApiWeb.Plugs.RateLimit, trusted_proxies: trusted_proxies

  jwt_secret =
    System.get_env("JWT_SECRET") ||
      raise """
      environment variable JWT_SECRET is missing.
      Generate a strong secret and set it for production.
      """

  access_ttl_seconds =
    case Integer.parse(System.get_env("JWT_ACCESS_TTL_SECONDS") || "900") do
      {ttl, ""} when ttl > 0 -> ttl
      _ -> 900
    end

  refresh_ttl_seconds =
    case Integer.parse(System.get_env("JWT_REFRESH_TTL_SECONDS") || "2592000") do
      {ttl, ""} when ttl > 0 -> ttl
      _ -> 2_592_000
    end

  config :edoc_api, EdocApi.Auth,
    jwt_secret: jwt_secret,
    access_ttl_seconds: access_ttl_seconds,
    refresh_ttl_seconds: refresh_ttl_seconds

  # Email configuration
  if System.get_env("SMTP_HOST") do
    config :edoc_api, EdocApi.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: System.get_env("SMTP_HOST"),
      username: System.get_env("SMTP_USERNAME"),
      password: System.get_env("SMTP_PASSWORD"),
      port: String.to_integer(System.get_env("SMTP_PORT") || "587"),
      ssl: System.get_env("SMTP_SSL") in ~w(true 1),
      tls: System.get_env("SMTP_TLS") in ~w(true 1) || :never,
      retries: String.to_integer(System.get_env("SMTP_RETRIES") || "2")
  else
    # Default to local for development
    config :edoc_api, EdocApi.Mailer, adapter: Swoosh.Adapters.Local
  end

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :edoc_api, EdocApiWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your endpoint, ensuring
  # no data is ever sent via http, always redirecting to https:
  #
  #     config :edoc_api, EdocApiWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :edoc_api, EdocApi.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
