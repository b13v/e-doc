defmodule EdocApiWeb.SessionController do
  use EdocApiWeb, :controller

  alias EdocApi.Accounts
  alias EdocApi.Companies
  alias EdocApi.Monetization

  def new(conn, _params) do
    render(conn, :new, page_title: gettext("Sign In"))
  end

  def create(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate_user(email, password) do
      {:ok, user} ->
        if user.verified_at == nil do
          conn
          |> put_flash(
            :error,
            gettext("Please verify your email address before signing in.")
          )
          |> redirect(to: "/verify-email-pending?email=#{email}")
        else
          _ = Monetization.accept_pending_memberships_for_user(user)

          redirect_path =
            cond do
              user.is_platform_admin ->
                "/admin/billing"

              Companies.get_company_by_user_id(user.id) == nil ->
                "/company/setup"

              true ->
                "/company"
            end

          # Store authenticated user id in session
          conn
          |> configure_session(renew: true)
          |> put_session(:user_id, user.id)
          |> assign(:current_user, user)
          |> put_flash(:info, gettext("Welcome!"))
          |> redirect(to: redirect_path)
        end

      {:error, :business_rule, _details} ->
        conn
        |> put_flash(:error, gettext("Invalid email address or password."))
        |> render(:new, page_title: gettext("Sign In"))
    end
  end

  def delete(conn, _params) do
    conn
    |> configure_session(drop: true)
    |> put_flash(:info, gettext("Signed out successfully."))
    |> redirect(to: "/")
  end
end
