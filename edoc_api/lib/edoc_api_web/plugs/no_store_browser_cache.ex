defmodule EdocApiWeb.Plugs.NoStoreBrowserCache do
  @moduledoc """
  Prevents authenticated HTML pages from being restored from browser cache.

  This matters after logout: the session is gone, but browser Back can otherwise
  show a previously rendered protected page from memory without hitting the server.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_header("cache-control", "private, no-store, max-age=0")
    |> put_resp_header("pragma", "no-cache")
    |> put_resp_header("expires", "0")
  end
end
