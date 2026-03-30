defmodule EdocApiWeb.AboutControllerTest do
  use EdocApiWeb.ConnCase, async: false

  describe "GET /about" do
    test "renders updated about copy in Russian by default", %{conn: conn} do
      conn = get(conn, "/about")

      body = html_response(conn, 200)

      assert body =~ "Edocly"
      refute body =~ "EdocAPI"
      refute body =~ "и несколько валют"
      refute body =~ ", английский"
    end
  end
end
