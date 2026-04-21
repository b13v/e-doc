defmodule EdocApiWeb.Plugs.RequirePlatformAdmin do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    case conn.assigns[:current_user] do
      %{is_platform_admin: true} ->
        conn

      _ ->
        conn
        |> put_resp_content_type("text/html")
        |> send_resp(:forbidden, "Forbidden")
        |> halt()
    end
  end
end
