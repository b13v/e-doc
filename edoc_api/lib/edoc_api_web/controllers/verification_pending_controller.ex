defmodule EdocApiWeb.VerificationPendingController do
  use EdocApiWeb, :controller

  require Logger

  alias EdocApi.Accounts
  alias EdocApi.EmailVerification
  alias EdocApi.EmailSender

  def new(conn, %{"email" => email}) do
    _ = maybe_resend_verification_email(email, conn.assigns[:locale] || "ru")

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

  defp maybe_resend_verification_email(email, locale) when is_binary(email) do
    case Accounts.get_user_by_email(email) do
      %Accounts.User{verified_at: nil} = user ->
        case EmailVerification.can_resend?(user.id) do
          {:ok, :allowed} ->
            with {:ok, %{token: token}} <- EmailVerification.create_token_for_user(user.id),
                 {:ok, _} <- EmailSender.send_verification_email(user.email, token, locale) do
              :ok
            else
              {:error, reason} ->
                Logger.warning("Failed to queue verification email from pending page: #{inspect(reason)}")
                :error
            end

          {:error, :rate_limited} ->
            :rate_limited
        end

      _ ->
        :noop
    end
  end

  defp redirect_after_verification(conn, message) do
    conn
    |> configure_session(renew: true)
    |> put_flash(:info, message)
    |> redirect(to: "/login")
  end
end
