defmodule EdocApiWeb.SignupController do
  use EdocApiWeb, :controller

  require Logger

  alias EdocApi.Accounts
  alias EdocApi.EmailVerification
  alias EdocApi.EmailSender

  def new(conn, params) do
    invited_email = normalize_invited_email(Map.get(params, "email"))
    render(conn, :new, page_title: gettext("Sign Up"), invited_email: invited_email)
  end

  def create(
        conn,
        %{
          "email" => email,
          "password" => password,
          "password_confirmation" => password_confirmation
        } = params
      ) do
    if password != password_confirmation do
      conn
      |> put_flash(:error, gettext("Passwords do not match."))
      |> render(:new, page_title: gettext("Sign Up"), invited_email: email)
    else
      case Accounts.register_user(%{
             "email" => email,
             "password" => password,
             "legal_terms_accepted" => Map.get(params, "legal_terms_accepted")
           }) do
        {:ok, user} ->
          {:ok, %{token: token}} = EmailVerification.create_token_for_user(user.id)

          case EmailSender.send_verification_email(
                 user.email,
                 token,
                 conn.assigns[:locale] || "ru"
               ) do
            {:ok, _} ->
              Logger.info("Verification email sent to #{masked_email(email)}")

            {:error, reason} ->
              Logger.error(
                "Failed to send verification email to #{masked_email(email)}: #{inspect(reason)}"
              )
          end

          conn
          |> put_flash(:info, gettext("Account created! Please verify your email to continue."))
          |> redirect(to: "/verify-email-pending?email=#{email}")

        {:error, :validation, changeset: changeset} ->
          if duplicate_email_error?(changeset) do
            _ =
              resend_verification_for_existing_unverified_account(
                email,
                conn.assigns[:locale] || "ru"
              )

            conn
            |> put_flash(
              :info,
              gettext("If the email is eligible, verification instructions will be sent shortly.")
            )
            |> redirect(to: "/verify-email-pending?email=#{URI.encode_www_form(email)}")
          else
            error_message = format_changeset_errors(changeset)

            conn
            |> put_flash(:error, error_message)
            |> render(:new, page_title: gettext("Sign Up"), invited_email: email)
          end

        {:error, changeset} ->
          error_message = format_changeset_errors(changeset)

          conn
          |> put_flash(:error, error_message)
          |> render(:new, page_title: gettext("Sign Up"), invited_email: email)
      end
    end
  end

  defp format_changeset_errors(changeset) do
    if legal_terms_acceptance_error?(changeset) do
      gettext("You must accept the terms of use and privacy policy.")
    else
      format_generic_changeset_errors(changeset)
    end
  end

  defp format_generic_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map(fn {k, v} -> "#{k}: #{Enum.join(v, ", ")}" end)
    |> Enum.join("; ")
  end

  defp legal_terms_acceptance_error?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn
      {:legal_terms_accepted, _error} -> true
      _ -> false
    end)
  end

  defp duplicate_email_error?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn
      {:email, {_msg, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end

  defp masked_email(email) when is_binary(email) do
    case String.split(email, "@", parts: 2) do
      [local, domain] when byte_size(local) > 1 ->
        String.slice(local, 0, 1) <> "***@" <> domain

      [local, domain] ->
        local <> "***@" <> domain

      _ ->
        "***"
    end
  end

  defp normalize_invited_email(nil), do: ""

  defp normalize_invited_email(email) when is_binary(email) do
    email |> String.trim()
  end

  defp resend_verification_for_existing_unverified_account(email, locale) when is_binary(email) do
    case Accounts.get_user_by_email(email) do
      %Accounts.User{verified_at: nil} = user ->
        with {:ok, %{token: token}} <- EmailVerification.create_token_for_user(user.id),
             {:ok, _} <- EmailSender.send_verification_email(user.email, token, locale) do
          :ok
        else
          {:error, reason} ->
            Logger.warning(
              "Failed to resend verification email for existing account: #{inspect(reason)}"
            )

            :error
        end

      _ ->
        :noop
    end
  end
end
