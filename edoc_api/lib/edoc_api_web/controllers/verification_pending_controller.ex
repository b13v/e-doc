defmodule EdocApiWeb.VerificationPendingController do
  use EdocApiWeb, :controller

  alias EdocApi.EmailVerification

  def new(conn, %{"email" => email}) do
    render(conn, :new, email: email, page_title: gettext("Verify Your Email"))
  end

  def new(conn, _params) do
    conn
    |> put_flash(:error, gettext("Please provide your email address."))
    |> redirect(to: "/signup")
  end

  def verify(conn, %{"token" => token}) do
    case EmailVerification.verify_token(token) do
      {:ok, _user_id} ->
        redirect_after_verification(
          conn,
          gettext("Your email address has been verified. You can now sign in.")
        )

      {:error, :already_verified} ->
        redirect_after_verification(
          conn,
          gettext("Your email address is already verified. Please sign in.")
        )

      {:error, :invalid_or_expired_token} ->
        conn
        |> put_flash(
          :error,
          gettext("Invalid or expired verification token. Please request a new one.")
        )
        |> redirect(to: "/verify-email-pending")
    end
  end

  def verify(conn, _params) do
    conn
    |> put_flash(:error, gettext("Missing verification token."))
    |> redirect(to: "/signup")
  end

  defp redirect_after_verification(conn, message) do
    conn
    |> configure_session(renew: true)
    |> put_flash(:info, message)
    |> redirect(to: "/login")
  end
end
