defmodule EdocApiWeb.SignupController do
  use EdocApiWeb, :controller

  require Logger

  alias EdocApi.Accounts
  alias EdocApi.EmailVerification
  alias EdocApi.EmailVerification.Token

  def new(conn, _params) do
    render(conn, :new, page_title: "Sign Up")
  end

  def create(conn, %{
        "email" => email,
        "password" => password,
        "password_confirmation" => password_confirmation
      }) do
    if password != password_confirmation do
      conn
      |> put_flash(:error, "Passwords do not match")
      |> render(:new, page_title: "Sign Up")
    else
      case Accounts.register_user(%{"email" => email, "password" => password}) do
        {:ok, user} ->
          {:ok, token} = EmailVerification.create_token_for_user(user.id)
          send_verification_email(user.email, token)

          conn
          |> put_flash(:info, "Account created! Please check your email to verify your account.")
          |> redirect(to: "/verify-email-pending?email=#{email}")

        {:error, changeset} ->
          error_message = format_changeset_errors(changeset)

          conn
          |> put_flash(:error, error_message)
          |> render(:new, page_title: "Sign Up")
      end
    end
  end

  defp send_verification_email(email, %Token{token: token, expires_at: expires_at}) do
    # In production, this would send an actual email
    # For now, we'll log the verification link
    expiry_hours = round(DateTime.diff(expires_at, DateTime.utc_now()) / 3600)

    Logger.info("""
    [EMAIL MOCK] Verification email sent to #{email}
    Verification link: http://localhost:4000/verify-email?token=#{token}
    Expires in: #{expiry_hours} hours
    """)
  end

  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
    |> Enum.join("; ")
  end
end
