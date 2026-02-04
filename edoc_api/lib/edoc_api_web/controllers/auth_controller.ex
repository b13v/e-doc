defmodule EdocApiWeb.AuthController do
  use EdocApiWeb, :controller

  alias EdocApi.Accounts
  alias EdocApi.Auth.Token
  alias EdocApi.EmailVerification
  alias EdocApiWeb.ErrorMapper

  def signup(conn, params) do
    with {:ok, user} <- Accounts.register_user(params) do
      EmailVerification.create_token_for_user(user.id)

      conn
      |> put_status(:created)
      |> json(%{
        user: %{id: user.id, email: user.email, verified: false},
        message: "Verification email sent. Please check your email."
      })
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        ErrorMapper.validation(conn, changeset)

      {:error, reason} ->
        ErrorMapper.unprocessable(conn, "signup_failed", %{reason: inspect(reason)})
    end
  end

  def login(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        if user.verified_at != nil do
          {:ok, token, _claims} = Token.generate_access_token(user.id)

          conn
          |> json(%{
            user: %{id: user.id, email: user.email, verified: true},
            access_token: token
          })
        else
          conn
          |> put_status(:unauthorized)
          |> json(%{
            error: "email_not_verified",
            message: "Please verify your email before logging in.",
            verified: false
          })
        end

      {:error, :invalid_credentials} ->
        ErrorMapper.unauthorized(conn, "invalid_credentials")

      _ ->
        ErrorMapper.unprocessable(conn, "login_failed")
    end
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
        conn
        |> put_status(:unauthorized)
        |> json(%{
          error: "invalid_or_expired_token",
          message: "Invalid or expired verification token"
        })
    end
  end

  def resend_verification(conn, %{"email" => email}) do
    case Accounts.get_user_by_email(email) do
      nil ->
        ErrorMapper.not_found(conn, "user_not_found")

      user ->
        if user.verified_at != nil do
          json(conn, %{
            success: true,
            message: "Email is already verified"
          })
        else
          case EmailVerification.can_resend?(user.id) do
            {:ok, :allowed} ->
              EmailVerification.create_token_for_user(user.id)

              json(conn, %{
                success: true,
                message: "Verification email sent"
              })

            {:error, :rate_limited} ->
              ErrorMapper.unprocessable(conn, "rate_limited", %{
                message: "Too many requests. Please try again later."
              })
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
end
