defmodule EdocApiWeb.SessionControllerTest do
  use EdocApiWeb.ConnCase, async: false

  import EdocApi.TestFixtures

  alias EdocApi.Accounts
  alias EdocApi.Companies
  alias EdocApi.Monetization

  test "login with invalid csrf token redirects back to login with retry flash", %{conn: conn} do
    user = create_user!()
    Accounts.mark_email_verified!(user.id)

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> put_private(:plug_skip_csrf_protection, false)
      |> post("/login", %{
        "_csrf_token" => "invalid-token",
        "email" => user.email,
        "password" => "wrong-password"
      })

    assert redirected_to(conn) == "/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             Gettext.gettext(EdocApiWeb.Gettext, "Your session expired. Please sign in again.")
  end

  test "login with invalid csrf token uses kazakh retry flash when locale is kk", %{conn: conn} do
    user = create_user!()
    Accounts.mark_email_verified!(user.id)

    conn =
      conn
      |> Plug.Test.init_test_session(%{locale: "kk"})
      |> put_private(:plug_skip_csrf_protection, false)
      |> post("/login", %{
        "_csrf_token" => "invalid-token",
        "email" => user.email,
        "password" => "wrong-password"
      })

    assert redirected_to(conn) == "/login"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Сессияның мерзімі аяқталды. Қайта кіріңіз."
  end

  test "html login activates invited memberships", %{conn: conn} do
    owner = create_user!()
    Accounts.mark_email_verified!(owner.id)
    company = create_company!(owner)

    invited = create_user!(%{"email" => "invitee2@example.com"})
    Accounts.mark_email_verified!(invited.id)

    assert {:ok, _membership} =
             Monetization.invite_member(company.id, %{
               "email" => invited.email,
               "role" => "member"
             })

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> post("/login", %{"email" => invited.email, "password" => "password123"})

    assert redirected_to(conn) == "/company"
    assert get_session(conn, :user_id) == invited.id
    assert Companies.get_company_by_user_id(invited.id).id == company.id
  end

  test "login with valid csrf and wrong password shows invalid credentials", %{conn: conn} do
    user = create_user!()
    Accounts.mark_email_verified!(user.id)

    login_page_conn = get(conn, "/login")
    body = html_response(login_page_conn, 200)
    csrf_token = extract_csrf_token(body)

    conn =
      login_page_conn
      |> recycle()
      |> post("/login", %{
        "_csrf_token" => csrf_token,
        "email" => user.email,
        "password" => "wrong-password"
      })

    assert html_response(conn, 200)
    assert Phoenix.Flash.get(conn.assigns.flash, :error)
  end

  defp extract_csrf_token(body) do
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, body)
    token
  end
end
