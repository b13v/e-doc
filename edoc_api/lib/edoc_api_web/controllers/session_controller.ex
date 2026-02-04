defmodule EdocApiWeb.SessionController do
  use EdocApiWeb, :controller

  alias EdocApi.Accounts
  alias EdocApi.Auth.Token
  alias EdocApi.Companies

  def new(conn, _params) do
    render(conn, :new, page_title: "Login")
  end

  def create(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        if user.verified_at == nil do
          conn
          |> put_flash(:error, "Please verify your email before logging in.")
          |> redirect(to: "/verify-email-pending?email=#{email}")
        else
          # Generate JWT token
          {:ok, token, _claims} = Token.generate_access_token(user.id)

          # Check if user has a company set up
          redirect_path =
            case Companies.get_company_by_user_id(user.id) do
              nil -> "/company/setup"
              _company -> "/invoices"
            end

          # Store token in session for htmx requests
          conn
          |> put_session(:user_id, user.id)
          |> put_session(:token, token)
          |> assign(:current_user, user)
          |> assign(:token, token)
          |> put_flash(:info, "Welcome back!")
          |> redirect(to: redirect_path)
        end

      {:error, _reason} ->
        conn
        |> put_flash(:error, "Invalid email or password")
        |> render(:new, page_title: "Login")
    end
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Logged out successfully")
    |> redirect(to: "/")
  end
end
