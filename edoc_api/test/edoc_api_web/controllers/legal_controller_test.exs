defmodule EdocApiWeb.LegalControllerTest do
  use EdocApiWeb.ConnCase, async: true

  describe "GET /privacy-policy" do
    test "renders Russian privacy policy by default", %{conn: conn} do
      conn = get(conn, "/privacy-policy")
      body = html_response(conn, 200)

      assert body =~ "Политика конфиденциальности сервиса Edocly.app"
      assert body =~ "Дата вступления в силу:"
      assert body =~ "Какие данные мы можем собирать"
      assert body =~ "ИП Асылбекова А.С."
      assert body =~ "info@edocly.app"
      assert body =~ ~s(href="/terms-of-use")
    end

    test "renders Kazakh privacy policy when locale is Kazakh", %{conn: conn} do
      conn =
        conn
        |> put_req_cookie("locale", "kk")
        |> get("/privacy-policy")

      body = html_response(conn, 200)

      assert body =~ "Edocly.app сервисінің құпиялылық саясаты"
      assert body =~ "Күшіне ену күні:"
      assert body =~ "Қандай деректерді жинауымыз мүмкін"
      assert body =~ "ЖК Асылбекова А.С."
      assert body =~ "info@edocly.app"
      assert body =~ ~s(href="/terms-of-use")
      refute body =~ "Какие данные мы можем собирать"
    end
  end

  describe "GET /terms-of-use" do
    test "renders Russian terms by default", %{conn: conn} do
      conn = get(conn, "/terms-of-use")
      body = html_response(conn, 200)

      assert body =~ "Условия использования сервиса Edocly.app"
      assert body =~ "Тарифы и лимиты"
      assert body =~ "Стартовый"
      assert body =~ "Базовый"
      assert body =~ "ИП Асылбекова А.С."
      assert body =~ ~s(href="/privacy-policy")
    end

    test "renders Kazakh terms when locale is Kazakh", %{conn: conn} do
      conn =
        conn
        |> put_req_cookie("locale", "kk")
        |> get("/terms-of-use")

      body = html_response(conn, 200)

      assert body =~ "Edocly.app сервисін пайдалану шарттары"
      assert body =~ "Тарифтер мен лимиттер"
      assert body =~ "Бастапқы"
      assert body =~ "Негізгі"
      assert body =~ "ЖК Асылбекова А.С."
      assert body =~ ~s(href="/privacy-policy")
      refute body =~ "Тарифы и лимиты"
    end
  end
end
