defmodule EdocApiWeb.HealthController do
  use EdocApiWeb, :controller

  def index(conn, _params) do
    json(conn, %{ok: true, service: "edoc_api", version: "0.1.0"})
  end
end
