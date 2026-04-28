defmodule EdocApiWeb.AboutControllerTest do
  use EdocApiWeb.ConnCase, async: false

  describe "GET /about" do
    test "renders updated about copy in Russian by default", %{conn: conn} do
      conn = get(conn, "/about")

      body = html_response(conn, 200)

      assert body =~ "Edocly"
      assert body =~ ~s(about-story-card)
      assert body =~ ~s(about-feature-grid)
      assert body =~ ~s(about-cta-card)
      assert body =~ "Для бизнеса в Казахстане"
      assert body =~ ~s(href="/signup")
      refute body =~ "EdocAPI"
      refute body =~ "и несколько валют"
      refute body =~ ", английский"
    end
  end
end
