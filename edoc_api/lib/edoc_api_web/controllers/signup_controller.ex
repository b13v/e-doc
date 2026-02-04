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
          verification_url = verification_link(token)

          send_verification_email(user.email, verification_url)

          conn
          |> put_flash(:info, "Account created! Please verify your email to continue.")
          |> redirect(to: "/verify-email-pending?email=#{email}&token=#{token}")

        {:error, :validation, changeset: changeset} ->
          error_message = format_changeset_errors(changeset)

          # Check if it's an email already taken error
          if String.downcase(error_message) =~ ~r/email.*already.*taken|has already been taken/ do
            conn
            |> put_flash(
              :error,
              "An account with this email already exists. Please log in instead."
            )
            |> redirect(to: "/login")
          else
            conn
            |> put_flash(:error, error_message)
            |> render(:new, page_title: "Sign Up")
          end

        {:error, changeset} ->
          error_message = format_changeset_errors(changeset)

          conn
          |> put_flash(:error, error_message)
          |> render(:new, page_title: "Sign Up")
      end
    end
  end

  defp send_verification_email(email, verification_url) do
    # In production, this would send an actual email
    # For now, we'll log the verification link
    Logger.info("""
    [EMAIL MOCK] Verification email sent to #{email}
    Verification link: #{verification_url}
    """)
  end

  defp verification_link(token) do
    base_url = System.get_env("BASE_URL") || "http://localhost:4000"
    "#{base_url}/verify-email?token=#{token}"
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
