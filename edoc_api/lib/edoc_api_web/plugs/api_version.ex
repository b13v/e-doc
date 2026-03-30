defmodule EdocApiWeb.Plugs.ApiVersion do
  @moduledoc false

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    version = Keyword.get(opts, :version, "v1")
    put_resp_header(conn, "x-api-version", version)
  end
end
