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
        conn
        |> put_flash(
          :info,
          gettext("Your email address has been verified. You can now sign in.")
        )
        |> redirect(to: "/login")

      {:error, :already_verified} ->
        conn
        |> put_flash(
          :info,
          gettext("Your email address is already verified. Please sign in.")
        )
        |> redirect(to: "/login")

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
end
