defmodule EdocApiWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :edoc_api

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
end
