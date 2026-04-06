defmodule EdocApiWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :edoc_api
  use Gettext, backend: EdocApiWeb.Gettext

  import Phoenix.Controller, only: [fetch_flash: 2, put_flash: 3, redirect: 2]

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  socket("/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: {EdocApiWeb.SessionOptions, :options, []}]]
  )

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug(Plug.Static,
    at: "/",
    from: :edoc_api,
    gzip: false,
    only: EdocApiWeb.static_paths()
  )

  if Code.ensure_loaded?(Tidewave) do
    plug(Tidewave)
  end

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    plug(Phoenix.CodeReloader)
    plug(Phoenix.Ecto.CheckRepoStatus, otp_app: :edoc_api)
  end

  plug(Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"
  )

  plug(Plug.RequestId)
  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library(),
    length: 10_000_000
  )

  plug(Plug.MethodOverride)
  plug(Plug.Head)
  plug(EdocApiWeb.SessionOptions)
  plug(EdocApiWeb.Router)

  def call(conn, opts) do
    super(conn, opts)
  rescue
    error in Plug.Conn.WrapperError ->
      case error.reason do
        %Plug.CSRFProtection.InvalidCSRFTokenError{} = csrf_error ->
          handle_invalid_csrf(conn, csrf_error, error.stack)

        _other ->
          reraise error, __STACKTRACE__
      end

    error in Plug.CSRFProtection.InvalidCSRFTokenError ->
      handle_invalid_csrf(conn, error, __STACKTRACE__)
  end

  defp handle_invalid_csrf(%Plug.Conn{method: "POST", request_path: "/login"} = conn, _error, _stack) do
    conn
    |> fetch_flash([])
    |> put_flash(:error, gettext("Your session expired. Please sign in again."))
    |> redirect(to: "/login")
  end

  defp handle_invalid_csrf(_conn, error, stack) do
    reraise error, stack
  end
end
