defmodule EdocApiWeb.SessionOptions do
  @moduledoc false

  @behaviour Plug

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    conn
    |> Plug.Session.call(Plug.Session.init(options()))
  end

  @spec options() :: keyword()
  def options do
    session_secure = Application.get_env(:edoc_api, :secure_cookies, false)

    session_signing_salt =
      Application.get_env(:edoc_api, :session_signing_salt, "dev-session-signing-salt")

    [
      store: :cookie,
      key: "_edoc_api_key",
      signing_salt: session_signing_salt,
      same_site: if(session_secure, do: "Strict", else: "Lax"),
      secure: session_secure,
      http_only: true
    ]
  end
end
