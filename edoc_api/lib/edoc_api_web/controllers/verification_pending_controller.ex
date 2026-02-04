defmodule EdocApiWeb.VerificationPendingController do
  use EdocApiWeb, :controller

  alias EdocApi.EmailVerification

  def new(conn, %{"email" => email, "token" => token}) do
    render(conn, :new, email: email, token: token, page_title: "Verify Your Email")
  end

  def new(conn, %{"email" => email}) do
    render(conn, :new, email: email, page_title: "Verify Your Email")
  end

  def new(conn, _params) do
    conn
    |> put_flash(:error, "Please provide your email address")
    |> redirect(to: "/signup")
  end

  def verify(conn, %{"token" => token}) do
    case EmailVerification.verify_token(token) do
      {:ok, _user_id} ->
        conn
        |> put_flash(:info, "Email verified successfully! You can now log in.")
        |> redirect(to: "/login")

      {:error, :already_verified} ->
        conn
        |> put_flash(:info, "Email was already verified. Please log in.")
        |> redirect(to: "/login")

      {:error, :invalid_or_expired_token} ->
        conn
        |> put_flash(:error, "Invalid or expired verification token. Please request a new one.")
        |> redirect(to: "/verify-email-pending")
    end
  end

  def verify(conn, _params) do
    conn
    |> put_flash(:error, "Verification token is missing")
    |> redirect(to: "/signup")
  end
end
