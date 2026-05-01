defmodule EdocApiWeb.AuthController do
  use EdocApiWeb, :controller

  require Logger

  alias EdocApi.Accounts
  alias EdocApi.Auth.Token
  alias EdocApi.EmailVerification
  alias EdocApi.EmailSender
  alias EdocApi.TeamMemberships
  alias EdocApiWeb.ErrorMapper

  def signup(conn, params) do
    with {:ok, user} <- Accounts.register_user(params),
         {:ok, %{token: token}} <- EmailVerification.create_token_for_user(user.id),
         {:ok, _} <-
           EmailSender.send_verification_email(user.email, token, conn.assigns[:locale] || "ru") do
      # Avoid leaking verification token in the API response
      :ok

      conn
      |> put_status(:created)
      |> json(%{
        user: %{id: user.id, email: user.email, verified: false},
        message: "Verification email sent. Please check your email."
      })
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        if duplicate_email_error?(changeset) do
          _ =
            resend_verification_for_existing_unverified_account(
              params,
              conn.assigns[:locale] || "ru"
            )

          conn
          |> put_status(:accepted)
          |> json(%{
            message: "If the email is eligible, verification instructions will be sent shortly."
          })
        else
          ErrorMapper.validation(conn, changeset)
        end

      {:error, :validation, changeset: %Ecto.Changeset{} = changeset} ->
        if duplicate_email_error?(changeset) do
          _ =
            resend_verification_for_existing_unverified_account(
              params,
              conn.assigns[:locale] || "ru"
            )

          conn
          |> put_status(:accepted)
          |> json(%{
            message: "If the email is eligible, verification instructions will be sent shortly."
          })
        else
          ErrorMapper.validation(conn, changeset)
        end

      {:error, reason} ->
        Logger.warning("Signup failed: #{inspect(reason)}")

        ErrorMapper.unprocessable(conn, "signup_failed", %{
          message: "Unable to create account. Please try again."
        })
    end
  end

  def login(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        if user.verified_at != nil do
          _ = TeamMemberships.accept_pending_memberships_for_user(user)

          with {:ok, access_token, _claims} <- Token.generate_access_token(user.id),
               {:ok, refresh_token} <- Accounts.issue_refresh_token(user.id) do
            conn
            |> json(%{
              user: %{id: user.id, email: user.email, verified: true},
              access_token: access_token,
              refresh_token: refresh_token
            })
          else
            _ ->
              ErrorMapper.unprocessable(conn, "login_failed", %{
                message: "Unable to complete login. Please try again."
              })
          end
        else
          ErrorMapper.unauthorized(conn, "email_not_verified", %{
            message: "Please verify your email before logging in.",
            verified: false
          })
        end

      {:error, :business_rule, %{rule: :invalid_credentials}} ->
        ErrorMapper.unauthorized(conn, "invalid_credentials")

      {:error, :business_rule, %{rule: :account_locked}} ->
        ErrorMapper.unauthorized(conn, "invalid_credentials")
    end
  end

  def refresh(conn, %{"refresh_token" => refresh_token}) do
    case Accounts.rotate_refresh_token(refresh_token) do
      {:ok, user, replacement_refresh_token} ->
        if user.verified_at != nil do
          with {:ok, access_token, _claims} <- Token.generate_access_token(user.id) do
            json(conn, %{
              user: %{id: user.id, email: user.email, verified: true},
              access_token: access_token,
              refresh_token: replacement_refresh_token
            })
          else
            _ -> ErrorMapper.unprocessable(conn, "refresh_failed")
          end
        else
          ErrorMapper.unauthorized(conn, "email_not_verified", %{
            message: "Please verify your email before logging in.",
            verified: false
          })
        end

      {:error, :invalid_refresh_token} ->
        ErrorMapper.unauthorized(conn, "invalid_refresh_token")

      {:error, :refresh_token_issue_failed} ->
        ErrorMapper.unprocessable(conn, "refresh_failed")
    end
  end

  def refresh(conn, _params) do
    ErrorMapper.bad_request(conn, "refresh_token_required")
  end

  def verify_email(conn, %{"token" => token}) do
    case EmailVerification.verify_token(token) do
      {:ok, _user_id} ->
        json(conn, %{
          success: true,
          message: "Email verified successfully",
          verified: true
        })

      {:error, :already_verified} ->
        json(conn, %{
          success: true,
          message: "Email was already verified",
          verified: true
        })

      {:error, :invalid_or_expired_token} ->
        ErrorMapper.unauthorized(conn, "invalid_or_expired_token", %{
          message: "Invalid or expired verification token"
        })
    end
  end

  def resend_verification(conn, %{"email" => email} = params) do
    conn = fetch_session(conn)
    locale = request_locale(conn, params)

    Gettext.put_locale(EdocApiWeb.Gettext, locale)

    case Accounts.get_user_by_email(email) do
      nil ->
        resend_verification_response(conn, :generic)

      user ->
        if user.verified_at != nil do
          resend_verification_response(conn, :generic)
        else
          case EmailVerification.can_resend?(user.id) do
            {:ok, :allowed} ->
              with {:ok, %{token: token}} <- EmailVerification.create_token_for_user(user.id),
                   {:ok, _} <-
                     EmailSender.send_verification_email(
                       user.email,
                       token,
                       conn.assigns[:locale] || "ru"
                     ) do
                resend_verification_response(conn, :sent)
              else
                {:error, reason} ->
                  Logger.warning("Verification resend failed: #{inspect(reason)}")
                  resend_verification_response(conn, :generic)
              end

            {:error, :rate_limited} ->
              resend_verification_response(conn, :rate_limited)
          end
        end
    end
  end

  def auth_status(conn, _params) do
    if conn.assigns.current_user do
      user = conn.assigns.current_user
      verified = Accounts.user_verified?(user.id)

      json(conn, %{
        authenticated: true,
        user_id: user.id,
        email: user.email,
        verified: verified,
        company_setup: user.company != nil
      })
    else
      json(conn, %{
        authenticated: false
      })
    end
  end

  defp duplicate_email_error?(%Ecto.Changeset{} = changeset) do
    Enum.any?(changeset.errors, fn
      {:email, {_msg, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end

  defp resend_verification_response(conn, status) do
    json(conn, %{
      success: true,
      status: to_string(status),
      message: resend_verification_message(status)
    })
  end

  defp resend_verification_message(:sent),
    do: gettext("Verification email sent. Please check your inbox.")

  defp resend_verification_message(:rate_limited),
    do: gettext("Please wait before requesting another verification email.")

  defp resend_verification_message(:generic),
    do: gettext("If the email is eligible, verification instructions will be sent shortly.")

  defp resend_verification_for_existing_unverified_account(%{"email" => email}, locale)
       when is_binary(email) do
    case Accounts.get_user_by_email(email) do
      %Accounts.User{verified_at: nil} = user ->
        with {:ok, %{token: token}} <- EmailVerification.create_token_for_user(user.id),
             {:ok, _} <- EmailSender.send_verification_email(user.email, token, locale) do
          :ok
        else
          {:error, reason} ->
            Logger.warning(
              "Failed to resend verification email for existing API signup account: #{inspect(reason)}"
            )

            :error
        end

      _ ->
        :noop
    end
  end

  defp request_locale(conn, params) do
    Map.get(params, "locale") ||
      conn.assigns[:locale] ||
      get_session(conn, :locale) ||
      "en"
  end
end
