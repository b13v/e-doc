defmodule EdocApiWeb.SignupControllerTest do
  use EdocApiWeb.ConnCase

  test "prefills invited email from query param", %{conn: conn} do
    conn = get(conn, "/signup?email=invitee@example.com")

    body = html_response(conn, 200)

    assert body =~ ~s(name="email")
    assert body =~ ~s(value="invitee@example.com")
  end
end
