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

  test "logout with invalid csrf token redirects to login with retry flash", %{conn: conn} do
    user = create_user!()
    Accounts.mark_email_verified!(user.id)

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> put_private(:plug_skip_csrf_protection, false)
      |> post("/logout", %{
        "_method" => "delete",
        "_csrf_token" => "invalid-token"
      })

    assert redirected_to(conn) == "/login"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             Gettext.gettext(EdocApiWeb.Gettext, "Your session expired. Please sign in again.")
  end

  test "logout POST without csrf token redirects to login with retry flash", %{conn: conn} do
    user = create_user!()
    Accounts.mark_email_verified!(user.id)

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> put_private(:plug_skip_csrf_protection, false)
      |> post("/logout", %{})

    assert redirected_to(conn) == "/login"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             Gettext.gettext(EdocApiWeb.Gettext, "Your session expired. Please sign in again.")
  end

  test "logout with invalid csrf token redirects even when session was not fetched", %{conn: conn} do
    conn =
      conn
      |> put_private(:plug_skip_csrf_protection, false)
      |> post("/logout", %{
        "_method" => "delete",
        "_csrf_token" => "invalid-token"
      })

    assert redirected_to(conn) == "/login"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             Gettext.gettext(EdocApiWeb.Gettext, "Your session expired. Please sign in again.")
  end

  test "logout with stale session cookie and invalid csrf token redirects to login", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.put_req_cookie("_edoc_api_key", "stale-invalid-cookie")
      |> put_private(:plug_skip_csrf_protection, false)
      |> post("/logout", %{
        "_method" => "delete",
        "_csrf_token" => "invalid-token"
      })

    assert redirected_to(conn) == "/login"

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             Gettext.gettext(EdocApiWeb.Gettext, "Your session expired. Please sign in again.")
  end

  test "authenticated browser pages are not stored in browser history cache", %{conn: conn} do
    user = create_user!()
    Accounts.mark_email_verified!(user.id)
    create_company!(user)

    conn =
      conn
      |> Plug.Test.init_test_session(%{user_id: user.id})
      |> get("/company")

    assert html_response(conn, 200)
    assert get_resp_header(conn, "cache-control") == ["private, no-store, max-age=0"]
    assert get_resp_header(conn, "pragma") == ["no-cache"]
    assert get_resp_header(conn, "expires") == ["0"]
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

  test "platform admin login redirects to billing backoffice without company setup", %{conn: conn} do
    admin = create_user!(%{"email" => "admin@edocly.com"})
    Accounts.mark_email_verified!(admin.id)

    admin
    |> Ecto.Changeset.change(is_platform_admin: true)
    |> EdocApi.Repo.update!()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> post("/login", %{"email" => admin.email, "password" => "password123"})

    assert redirected_to(conn) == "/admin/billing"
    assert get_session(conn, :user_id) == admin.id
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

  test "login page keeps desktop auth panes aligned without viewport over-stretch and has explicit dark-mode auth contrast hooks", %{conn: conn} do
    conn = get(conn, "/login")
    body = html_response(conn, 200)

    assert body =~ ~s(data-theme-toggle)
    assert body =~ ~s(data-theme-label)
    assert body =~ ~s(href="/password/forgot")
    assert body =~ ~s|window.toggleWorkspaceTheme = function()|
    assert body =~ ~s(>Dark<)
    assert body =~ ~s(data-public-nav-desktop)
    assert body =~ ~s(data-public-nav-mobile)
    assert body =~ ~s(public-auth-shell)
    assert body =~ ~s(public-auth-panel)
    assert body =~ ~s(public-auth-card)
    assert body =~ ~s(lg:items-start)
    assert body =~ ~s(lg:min-h-0)
    assert body =~ ~s(lg:self-stretch)
    assert body =~ ~s(lg:h-full)
    assert body =~ ~s(auth-form-card)
    assert body =~ ~s(auth-form-title)
    assert body =~ ~s(auth-form-label)
    assert body =~ ~s(auth-form-input)
    assert body =~ ~s(auth-form-divider-line)
    assert body =~ ~s(auth-form-link)
    assert body =~ ~s(auth-form-submit)
    assert body =~ ~s|html[data-theme="dark"] .auth-form-card|
    assert body =~ ~s|html[data-theme="dark"] .auth-form-title|
    assert body =~ ~s|html[data-theme="dark"] .auth-form-label|
    assert body =~ ~s|html[data-theme="dark"] .auth-form-input|
    assert body =~ ~s|html[data-theme="dark"] .auth-form-divider-line|
    assert body =~ ~s|html[data-theme="dark"] .auth-form-link|
    assert body =~ ~s|html[data-theme="dark"] .auth-form-submit|
    assert body =~ "Казахстан"
    assert body =~ ~s(dark:text-slate-100)
    assert body =~ ~s(dark:text-slate-200)
    assert body =~ ~s(dark:bg-slate-950)
    assert body =~ ~s(dark:ring-slate-600)
    refute body =~ ~s(public-auth-card order-1 flex)
    refute body =~ ~s(public-auth-card order-1 rounded-[30px] border border-stone-200 bg-white/95 p-6 shadow-xl ring-1 ring-stone-200/70 backdrop-blur dark:border-slate-700 dark:bg-slate-900/95 dark:ring-slate-700/70 lg:order-2 lg:h-full)
    refute body =~ ~s(data-theme-lock="light")

    assert body =~
             ~s|href="/" class="workspace-public-nav-link font-medium text-gray-600 hover:text-gray-900 dark:text-black dark:hover:text-black"|

    assert body =~
             ~s|href="/about" class="workspace-public-nav-link font-medium text-gray-600 hover:text-gray-900 dark:text-black dark:hover:text-black"|

    assert body =~ ~s|html[data-theme="dark"] .workspace-public-nav-link|
    assert body =~ ~s(workspace-locale-inactive)
    assert length(Regex.scan(~r/workspace-locale-inactive[^"]*dark:text-white/, body)) >= 2
    assert body =~ ~s(href="/signup")

    refute body =~
             ~s(workspace-locale-inactive rounded-full px-2.5 py-1 text-xs font-semibold uppercase tracking-wide text-black dark:text-black dark:hover:text-black)
  end

  test "public asset bundle endpoints referenced by auth pages are available", %{conn: conn} do
    # Regression: ISSUE-QA-001 — /login and /signup reference app.css/app.js but both returned 404
    # Found by /qa on 2026-04-12
    # Report: .gstack/qa-reports/qa-report-localhost-4000-2026-04-12.md
    conn = get(conn, "/assets/app.css")
    assert response(conn, 200)

    conn = build_conn() |> get("/assets/app.js")
    assert response(conn, 200)
  end

  defp extract_csrf_token(body) do
    [_, token] = Regex.run(~r/name="_csrf_token" value="([^"]+)"/, body)
    token
  end
end
