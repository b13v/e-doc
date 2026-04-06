defmodule EdocApiWeb.VerificationPendingControllerTest do
  use EdocApiWeb.ConnCase

  import EdocApi.TestFixtures
  import Swoosh.TestAssertions

  alias EdocApi.EmailVerification

  test "resend button does not render API JSON payload into the page", %{conn: conn} do
    conn = get(conn, "/verify-email-pending?email=example@example.com")
    body = html_response(conn, 200)

    assert body =~ ~s(id="resend-btn")
    assert body =~ ~s(hx-post="/v1/auth/resend-verification")
    assert body =~ ~s(hx-swap="none")
    refute body =~ ~s(hx-target="#resend-result")
    refute body =~ ~s(id="resend-result")
  end

  test "pending page queues verification email for existing unverified account", %{conn: conn} do
    email = "pending-#{System.unique_integer([:positive])}@example.com"
    _user = create_user!(%{"email" => email})

    conn = get(conn, "/verify-email-pending?email=#{URI.encode_www_form(email)}")
    assert html_response(conn, 200)

    assert_email_sent(fn sent ->
      Enum.any?(sent.to, fn {_name, addr} -> addr == email end) and
        String.contains?(sent.subject, "Edocly") and
        String.contains?(sent.text_body, "/verify-email?token=")
      end)
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
end
