defmodule EdocApiWeb.Plugs.ApiVersionTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias EdocApiWeb.Plugs.ApiVersion

  test "adds x-api-version response header" do
    conn = conn(:get, "/v1/health") |> ApiVersion.call(version: "v1")
    assert Plug.Conn.get_resp_header(conn, "x-api-version") == ["v1"]
  end
end
