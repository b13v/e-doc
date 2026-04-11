defmodule EdocApiWeb.PasswordResetController do
  use EdocApiWeb, :controller

  alias EdocApi.PasswordReset

  def new(conn, _params) do
    render(conn, :new, page_title: gettext("Forgot Password"))
  end

  def create(conn, %{"email" => email}) do
    _ = PasswordReset.request_reset(email, conn.assigns[:locale] || "ru")

    conn
    |> put_flash(
      :info,
      gettext(
        "If an account exists for that email, password reset instructions will be sent shortly."
      )
    )
    |> redirect(to: "/password/forgot")
  end

  def create(conn, _params) do
    conn
    |> put_flash(
      :info,
      gettext(
        "If an account exists for that email, password reset instructions will be sent shortly."
      )
    )
    |> redirect(to: "/password/forgot")
  end

  def edit(conn, %{"token" => token}) do
    case PasswordReset.verify_token(token) do
      {:ok, _token_payload} ->
        render(conn, :edit, page_title: gettext("Reset Password"), token: token)

      {:error, :invalid_or_expired} ->
        conn
        |> put_flash(:error, gettext("This password reset link is invalid or expired."))
        |> render(:edit,
          page_title: gettext("Reset Password"),
          invalid_token: true
        )
    end
  end

  def edit(conn, _params) do
    conn
    |> put_flash(:error, gettext("This password reset link is invalid or expired."))
    |> render(:edit, page_title: gettext("Reset Password"), invalid_token: true)
  end

  def update(conn, %{"token" => token} = params) do
    password_params =
      case Map.get(params, "password") do
        %{} = nested -> nested
        _ -> params
      end

    case PasswordReset.reset_password(
           token,
           Map.get(password_params, "password", ""),
           Map.get(password_params, "password_confirmation", "")
         ) do
      {:ok, :password_reset} ->
        conn
        |> put_flash(:info, gettext("Your password has been reset. Please sign in again."))
        |> redirect(to: "/login")

      {:error, :validation_failed, changeset} ->
        {_field, {message, opts}} = List.first(changeset.errors) || {:base, {"Invalid data", []}}

        conn
        |> put_flash(:error, EdocApiWeb.ErrorHelpers.translate_error({message, opts}))
        |> render(:edit,
          page_title: gettext("Reset Password"),
          token: token,
          changeset: changeset
        )

      {:error, :invalid_or_expired} ->
        conn
        |> put_flash(:error, gettext("This password reset link is invalid or expired."))
        |> render(:edit, page_title: gettext("Reset Password"), invalid_token: true)
    end
  end

  def update(conn, _params) do
    conn
    |> put_flash(:error, gettext("This password reset link is invalid or expired."))
    |> render(:edit, page_title: gettext("Reset Password"), invalid_token: true)
  end
end
