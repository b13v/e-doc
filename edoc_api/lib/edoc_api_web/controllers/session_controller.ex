defmodule EdocApiWeb.SessionController do
  use EdocApiWeb, :controller

  alias EdocApi.Accounts
  alias EdocApi.Companies

  def new(conn, _params) do
    render(conn, :new, page_title: "Login")
  end

  def create(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        if user.verified_at == nil do
          conn
          |> put_flash(
            :error,
            "Пожалуйста, подтвердите свой адрес электронной почты перед входом в систему."
          )
          |> redirect(to: "/verify-email-pending?email=#{email}")
        else
          # Check if user has a company set up
          redirect_path =
            case Companies.get_company_by_user_id(user.id) do
              nil -> "/company/setup"
              _company -> "/company"
            end

          # Store authenticated user id in session
          conn
          |> configure_session(renew: true)
          |> put_session(:user_id, user.id)
          |> assign(:current_user, user)
          |> put_flash(:info, "Добро пожаловать!")
          |> redirect(to: redirect_path)
        end

      {:error, :business_rule, _details} ->
        conn
        |> put_flash(:error, "Неверный адрес электронной почты или пароль.")
        |> render(:new, page_title: "Login")
    end
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, "Выход из системы выполнен успешно.")
    |> redirect(to: "/")
  end
end
