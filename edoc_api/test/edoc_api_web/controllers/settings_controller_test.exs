defmodule EdocApiWeb.SettingsControllerTest do
  use EdocApiWeb.ConnCase, async: false

  import EdocApi.TestFixtures

  alias EdocApi.Accounts

  setup do
    user = create_user!()
    Accounts.mark_email_verified!(user.id)

    %{user: user}
  end

  test "GET /settings redirects unauthenticated users to /login", %{conn: conn} do
    conn = get(conn, "/settings")
    assert redirected_to(conn) == "/login"
  end

  test "GET /settings renders settings page for authenticated user", %{conn: conn, user: user} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> get("/settings")

    body = html_response(conn, 200)
    assert body =~ "settings-profile-form"
    assert body =~ "settings-password-form"
    assert body =~ user.email
  end

  test "PUT /settings/profile persists first_name and last_name", %{conn: conn, user: user} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> put("/settings/profile", %{
        "profile" => %{
          "first_name" => "Ivan",
          "last_name" => "Petrov"
        }
      })

    assert redirected_to(conn) == "/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Профиль успешно обновлен."

    updated = Accounts.get_user(user.id)
    assert updated.first_name == "Ivan"
    assert updated.last_name == "Petrov"

    redirected =
      conn
      |> recycle()
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> get("/settings")

    body = html_response(redirected, 200)
    assert body =~ "Профиль успешно обновлен."
  end

  test "PUT /settings/password rejects invalid current password", %{conn: conn, user: user} do
    old_hash = Accounts.get_user(user.id).password_hash

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> put("/settings/password", %{
        "password" => %{
          "current_password" => "wrong-password",
          "password" => "new-password-123",
          "password_confirmation" => "new-password-123"
        }
      })

    assert redirected_to(conn) == "/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Текущий пароль указан неверно."
    assert Accounts.get_user(user.id).password_hash == old_hash

    redirected =
      conn
      |> recycle()
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> get("/settings")

    body = html_response(redirected, 200)
    assert body =~ "Текущий пароль указан неверно."
  end

  test "PUT /settings/password updates password hash with valid current password", %{
    conn: conn,
    user: user
  } do
    old_hash = Accounts.get_user(user.id).password_hash

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> put("/settings/password", %{
        "password" => %{
          "current_password" => "password123",
          "password" => "new-password-123",
          "password_confirmation" => "new-password-123"
        }
      })

    assert redirected_to(conn) == "/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Пароль успешно обновлен."

    updated = Accounts.get_user(user.id)
    assert updated.password_hash != old_hash
    assert Argon2.verify_pass("new-password-123", updated.password_hash)
    refute Argon2.verify_pass("password123", updated.password_hash)
  end

  test "PUT /settings/password localizes mismatch confirmation error in Russian", %{
    conn: conn,
    user: user
  } do
    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id, locale: "ru"})
      |> put("/settings/password", %{
        "password" => %{
          "current_password" => "password123",
          "password" => "new-password-123",
          "password_confirmation" => "different-password-123"
        }
      })

    assert redirected_to(conn) == "/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Новый пароль и подтверждение не совпадают."
  end

  test "PUT /settings/password localizes mismatch confirmation error in Kazakh", %{
    conn: conn,
    user: user
  } do
    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id, locale: "kk"})
      |> put("/settings/password", %{
        "password" => %{
          "current_password" => "password123",
          "password" => "new-password-123",
          "password_confirmation" => "different-password-123"
        }
      })

    assert redirected_to(conn) == "/settings"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) == "Жаңа құпиясөз және растау сәйкес келмейді."
  end

  test "authenticated navbar links account email to /settings", %{conn: conn, user: user} do
    _company = create_company!(user)

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> get("/company")

    body = html_response(conn, 200)

    assert body =~ ~s(href="/settings")
    assert body =~ user.email
  end
end
