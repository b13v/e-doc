defmodule EdocApiWeb.VerificationPendingControllerTest do
  use EdocApiWeb.ConnCase

  import EdocApi.TestFixtures

  alias EdocApi.EmailVerification

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

  test "resend button is wired to show browser-visible feedback", %{conn: conn} do
    conn = get(conn, "/verify-email-pending?email=example@example.com")
    body = html_response(conn, 200)

    assert body =~ ~s(id="resend-btn")
    assert body =~ ~s(hx-post="/v1/auth/resend-verification")
    assert body =~ ~s(hx-swap="none")
    assert body =~ ~s(id="resend-feedback")
    assert body =~ ~s(hx-on::after-request=)
  end

  test "pending page does not show register-again link", %{conn: conn} do
    conn = get(conn, "/verify-email-pending?email=example@example.com")
    body = html_response(conn, 200)

    refute body =~ ~s(class="mt-6 pt-6 border-t border-gray-200")
  end

  test "missing email redirects to signup", %{conn: conn} do
    conn = get(conn, "/verify-email-pending")

    assert redirected_to(conn) == "/signup"
    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "Пожалуйста, укажите свой адрес электронной почты."
  end

  test "pending page does not send a verification email on page load", %{conn: conn} do
    email = "pending-#{System.unique_integer([:positive])}@example.com"
    _user = create_user!(%{"email" => email})

    conn = get(conn, "/verify-email-pending?email=#{URI.encode_www_form(email)}")
    assert html_response(conn, 200)

    assert verification_email_count(email) == 0
  end

  test "successful verification renews the session and redirects to login", %{conn: conn} do
    user = create_user!()
    {:ok, %{token: token}} = EmailVerification.create_token_for_user(user.id)

    conn =
      conn
      |> Plug.Test.init_test_session(%{locale: "kk", session_marker: "keep-me"})
      |> get("/verify-email?token=#{token}")

    assert redirected_to(conn) == "/login"
    assert get_session(conn, :session_marker) == "keep-me"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) ==
             "Электрондық поштаңыз расталды. Енді жүйеге кіре аласыз."
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
