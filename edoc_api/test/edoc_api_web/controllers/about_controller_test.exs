defmodule EdocApiWeb.AboutControllerTest do
  use EdocApiWeb.ConnCase, async: false

  describe "GET /about" do
    test "renders updated about copy in Russian by default", %{conn: conn} do
      conn = get(conn, "/about")

      body = html_response(conn, 200)

      assert body =~ "Edocly"
      assert body =~ ~s(about-story-card)
      assert body =~ ~s(about-feature-grid)
      assert body =~ ~s(about-section-card)
      assert body =~ ~s(about-section-title)
      assert body =~ ~s(about-cta-card)
      assert body =~ ~s(about-cta-title)
      assert body =~ ~s(about-cta-copy)
      assert body =~ ~s(about-cta-secondary-link)
      assert body =~ ~s|html[data-theme="dark"] .about-section-card|
      assert body =~ ~s|html[data-theme="dark"] .about-section-title|
      assert body =~ ~s|html[data-theme="dark"] .about-cta-card|
      assert body =~ ~s|html[data-theme="dark"] .about-cta-title|
      assert body =~ ~s|html[data-theme="dark"] .about-cta-copy|
      assert body =~ ~s|html[data-theme="dark"] .about-cta-secondary-link|
      assert body =~ "Для бизнеса в Казахстане"
      assert body =~ "Договоры"
      assert body =~ "Покупатели"
      assert body =~ "НДС"
      assert body =~ "Безопасность"
      assert body =~ ~s(href="/signup")
      refute body =~ "EdocAPI"
      refute body =~ "и несколько валют"
      refute body =~ ", английский"
      refute body =~ ">Contracts<"
      refute body =~ ">CRM<"
      refute body =~ ">VAT<"
      refute body =~ ">Security<"
    end

    test "renders middle feature labels in Kazakh", %{conn: conn} do
      conn =
        conn
        |> put_req_cookie("locale", "kk")
        |> get("/about")

      body = html_response(conn, 200)

      assert body =~ "Келісімшарттар"
      assert body =~ "Сатып алушылар"
      assert body =~ "ҚҚС"
      assert body =~ "Қауіпсіздік"
      refute body =~ ">Contracts<"
      refute body =~ ">CRM<"
      refute body =~ ">VAT<"
      refute body =~ ">Security<"
    end
  end
end
