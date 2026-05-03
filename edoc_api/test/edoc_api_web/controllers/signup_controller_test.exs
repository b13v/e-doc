defmodule EdocApiWeb.SignupControllerTest do
  use EdocApiWeb.ConnCase

  import EdocApi.TestFixtures

  alias EdocApi.Monetization

  setup do
    original_mailer_config = Application.get_env(:edoc_api, EdocApi.Mailer, [])

    Application.put_env(:edoc_api, EdocApi.Mailer, adapter: Swoosh.Adapters.Local)

    case Swoosh.Adapters.Local.Storage.Memory.start() do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
    end

    Swoosh.Adapters.Local.Storage.Memory.delete_all()

    on_exit(fn ->
      Swoosh.Adapters.Local.Storage.Memory.delete_all()
      Application.put_env(:edoc_api, EdocApi.Mailer, original_mailer_config)
    end)

    :ok
  end

  test "prefills invited email from query param", %{conn: conn} do
    conn = get(conn, "/signup?email=invitee@example.com")

    body = html_response(conn, 200)

    assert body =~ ~s(name="email")
    assert body =~ ~s(value="invitee@example.com")
    assert body =~ ~s(data-theme-toggle)
    assert body =~ ~s(data-theme-label)
    assert body =~ ~s|window.toggleWorkspaceTheme = function()|
    assert body =~ ~s(data-public-nav-desktop)
    assert body =~ ~s(data-public-nav-mobile)
    assert body =~ ~s(workspace-app-header relative z-50)
    assert body =~ ~s(data-public-mobile-menu-panel)
    assert body =~ ~s(z-50 mt-3 w-72)
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
    assert body =~ ~s(auth-form-divider-chip)
    assert body =~ ~s(auth-form-link)
    assert body =~ ~s(auth-form-submit)
    assert body =~ ~s|html[data-theme="dark"] .auth-form-card|
    assert body =~ ~s|html[data-theme="dark"] .auth-form-title|
    assert body =~ ~s|html[data-theme="dark"] .auth-form-label|
    assert body =~ ~s|html[data-theme="dark"] .auth-form-input|
    assert body =~ ~s|html[data-theme="dark"] .auth-form-divider-chip|
    assert body =~ ~s|html[data-theme="dark"] .auth-form-link|
    assert body =~ ~s|html[data-theme="dark"] .auth-form-submit|

    assert body =~
             ~s|href="/" class="workspace-public-nav-link font-medium text-gray-600 hover:text-gray-900 dark:text-slate-100 dark:hover:text-white"|

    assert body =~
             ~s|href="/about" class="workspace-public-nav-link font-medium text-gray-600 hover:text-gray-900 dark:text-slate-100 dark:hover:text-white"|

    assert body =~ ~s(href="/login")
    assert body =~ "Казахстан"
    assert body =~ ~s(dark:text-slate-100)
    assert body =~ ~s(dark:text-slate-200)
    assert body =~ ~s(dark:bg-slate-950)
    assert body =~ ~s(dark:ring-slate-600)
    assert body =~ ~s(dark:text-slate-300)
    refute body =~ ~s(public-auth-card order-1 flex)

    refute body =~
             ~s(public-auth-card order-1 rounded-[30px] border border-stone-200 bg-white/95 p-6 shadow-xl ring-1 ring-stone-200/70 backdrop-blur dark:border-slate-700 dark:bg-slate-900/95 dark:ring-slate-700/70 lg:order-2 lg:h-full)

    assert body =~ ~s|html[data-theme="dark"] .workspace-public-nav-link|
    assert length(Regex.scan(~r/workspace-locale-inactive[^"]*dark:text-white/, body)) >= 2
    refute body =~ ~s(data-theme-lock="light")

    refute body =~
             ~s(workspace-locale-inactive rounded-full px-2.5 py-1 text-xs font-semibold uppercase tracking-wide text-black dark:text-black dark:hover:text-black)
  end

  test "signup form requires legal terms acceptance with russian legal links", %{conn: conn} do
    conn = get(conn, "/signup")

    body = html_response(conn, 200)

    assert body =~ ~s(type="checkbox")
    assert body =~ ~s(name="legal_terms_accepted")
    assert body =~ ~s(required)
    assert body =~ "Регистрируясь, вы принимаете"
    assert body =~ ~s(href="/terms-of-use")
    assert body =~ "Условия использования"
    assert body =~ ~s(href="/privacy-policy")
    assert body =~ "Политику конфиденциальности"
  end

  test "signup form localizes legal terms acceptance in kazakh", %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{locale: "kk"})
      |> get("/signup")

    body = html_response(conn, 200)

    assert body =~ "Тіркелу арқылы сіз"
    assert body =~ "Пайдалану шарттарын"
    assert body =~ "Құпиялық саясатын"
    assert body =~ ~s(href="/terms-of-use")
    assert body =~ ~s(href="/privacy-policy")
  end

  test "signup rejects unchecked legal terms acceptance", %{conn: conn} do
    email = "legal-missing-#{System.unique_integer([:positive])}@example.com"

    conn =
      conn
      |> put_private(:plug_skip_csrf_protection, true)
      |> put_req_header("accept", "text/html")
      |> post("/signup", %{
        "email" => email,
        "password" => "password123",
        "password_confirmation" => "password123"
      })

    assert html_response(conn, 200) =~
             "Необходимо принять условия использования и политику конфиденциальности."

    assert EdocApi.Accounts.get_user_by_email(email) == nil
  end

  test "signup sends russian verification email with Edocly branding by default", %{conn: conn} do
    email = "verify-ru-#{System.unique_integer([:positive])}@example.com"

    conn =
      conn
      |> put_private(:plug_skip_csrf_protection, true)
      |> put_req_header("accept", "text/html")
      |> post("/signup", %{
        "email" => email,
        "password" => "password123",
        "password_confirmation" => "password123",
        "legal_terms_accepted" => "true"
      })

    assert redirected_to(conn) =~ "/verify-email-pending?email="
    conn = get(conn, redirected_to(conn))
    assert html_response(conn, 200)

    assert verification_email_count(email) == 1

    user = EdocApi.Accounts.get_user_by_email(email)
    assert %DateTime{} = Map.get(user, :terms_accepted_at)
    assert %DateTime{} = Map.get(user, :privacy_accepted_at)
    assert Map.get(user, :legal_acceptance_version)
  end

  test "signup sends kazakh verification email when locale is kk", %{conn: conn} do
    email = "verify-kk-#{System.unique_integer([:positive])}@example.com"

    conn =
      conn
      |> Plug.Test.init_test_session(%{locale: "kk"})
      |> put_private(:plug_skip_csrf_protection, true)
      |> put_req_header("accept", "text/html")
      |> post("/signup", %{
        "email" => email,
        "password" => "password123",
        "password_confirmation" => "password123",
        "legal_terms_accepted" => "true"
      })

    assert redirected_to(conn) =~ "/verify-email-pending?email="
    conn = get(conn, redirected_to(conn))
    assert html_response(conn, 200)

    assert verification_email_count(email) == 1
  end

  test "invited user signup resends verification email when account exists but is unverified", %{
    conn: conn
  } do
    owner = create_user!()
    company = create_company!(owner)
    invited_email = "invited-#{System.unique_integer([:positive])}@example.com"

    assert {:ok, _membership} =
             Monetization.invite_member(company.id, %{
               "email" => invited_email,
               "role" => "member"
             })

    _existing_unverified_user = create_user!(%{"email" => invited_email})

    conn =
      conn
      |> put_private(:plug_skip_csrf_protection, true)
      |> put_req_header("accept", "text/html")
      |> post("/signup", %{
        "email" => invited_email,
        "password" => "password123",
        "password_confirmation" => "password123",
        "legal_terms_accepted" => "true"
      })

    assert redirected_to(conn) =~
             "/verify-email-pending?email=#{URI.encode_www_form(invited_email)}"

    assert Phoenix.Flash.get(conn.assigns.flash, :info)
    conn = get(conn, redirected_to(conn))
    assert html_response(conn, 200)

    assert verification_email_count(invited_email) == 1
  end

  defp verification_email_count(email) do
    Swoosh.Adapters.Local.Storage.Memory.all()
    |> Enum.count(&verification_email_for?(&1, email))
  end

  defp verification_email_for?(sent, email) do
    Enum.any?(sent.to, fn {_name, addr} -> addr == email end) and
      String.contains?(sent.subject, "Edocly") and
      String.contains?(sent.text_body, "/verify-email?token=")
  end
end
