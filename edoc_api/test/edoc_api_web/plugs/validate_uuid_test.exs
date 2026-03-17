defmodule EdocApiWeb.Plugs.ValidateUuidTest do
  use EdocApiWeb.ConnCase, async: true

  alias EdocApiWeb.Plugs.ValidateUuid

  test "allows valid UUID params", %{conn: conn} do
    conn =
      conn
      |> Map.put(:params, %{"id" => Ecto.UUID.generate()})
      |> ValidateUuid.call(ValidateUuid.init([]))

    refute conn.halted
  end

  test "rejects malformed UUID params", %{conn: conn} do
    conn =
      conn
      |> Map.put(:params, %{"id" => "not-a-uuid"})
      |> ValidateUuid.call(ValidateUuid.init([]))

    assert conn.halted
    assert conn.status == 400
  end
end
