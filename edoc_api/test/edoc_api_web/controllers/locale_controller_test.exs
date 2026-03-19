defmodule EdocApiWeb.LocaleControllerTest do
  use EdocApiWeb.ConnCase, async: false

  describe "GET /locale/:locale" do
    test "persists the locale in session and cookie and redirects back", %{conn: conn} do
      conn = get(conn, "/locale/kk?return_to=/login")

      assert redirected_to(conn) == "/login"
      assert get_session(conn, :locale) == "kk"

      assert get_resp_header(conn, "set-cookie")
             |> Enum.any?(&String.contains?(&1, "locale=kk"))
    end

    test "normalizes unsafe return paths to root", %{conn: conn} do
      conn = get(conn, "/locale/kk?return_to=https://evil.example.com")

      assert redirected_to(conn) == "/"
    end
  end

  describe "localized browser pages" do
    test "renders login in Russian by default", %{conn: conn} do
      conn = get(conn, "/login")

      body = html_response(conn, 200)

      assert body =~ ~s(<html lang="ru")
      assert body =~ "Вход в аккаунт"
      assert body =~ "Электронная почта"
      assert body =~ "Вход"
    end

    test "renders login in Kazakh when locale cookie is set", %{conn: conn} do
      conn =
        conn
        |> put_req_cookie("locale", "kk")
        |> get("/login")

      body = html_response(conn, 200)

      assert body =~ ~s(<html lang="kk")
      assert body =~ "Аккаунтыңызға кіріңіз"
      assert body =~ "Электрондық пошта"
      assert body =~ "Кіру"
    end
  end
end
