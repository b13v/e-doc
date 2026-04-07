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
        "password_confirmation" => "password123"
      })

    assert redirected_to(conn) =~ "/verify-email-pending?email="
    conn = get(conn, redirected_to(conn))
    assert html_response(conn, 200)

    assert verification_email_count(email) == 1
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
        "password_confirmation" => "password123"
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
        "password_confirmation" => "password123"
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
