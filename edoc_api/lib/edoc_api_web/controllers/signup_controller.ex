defmodule EdocApiWeb.SignupController do
  use EdocApiWeb, :controller

  require Logger

  alias EdocApi.Accounts
  alias EdocApi.EmailVerification
  alias EdocApi.EmailSender

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

          case EmailSender.send_verification_email(user.email, token) do
            {:ok, _} ->
              Logger.info("Verification email sent to #{email}")

            {:error, reason} ->
              Logger.error("Failed to send verification email to #{email}: #{inspect(reason)}")
          end

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
