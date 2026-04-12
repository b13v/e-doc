defmodule EdocApiWeb.SettingsController do
  use EdocApiWeb, :controller

  alias EdocApi.Accounts
  alias EdocApiWeb.ErrorHelpers

  def edit(conn, _params) do
    user = conn.assigns.current_user

    render(conn, :edit,
      page_title: gettext("Settings"),
      profile: %{
        "first_name" => user.first_name || "",
        "last_name" => user.last_name || ""
      }
    )
  end

  def update_profile(conn, %{"profile" => profile_params}) do
    user = conn.assigns.current_user

    case Accounts.update_user_profile(user.id, profile_params) do
      {:ok, _updated_user} ->
        conn
        |> put_flash(:info, gettext("Profile updated successfully."))
        |> redirect(to: "/settings")

      {:error, :validation, changeset: changeset} ->
        conn
        |> put_flash(:error, first_changeset_error(changeset))
        |> redirect(to: "/settings")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, gettext("User not found."))
        |> redirect(to: "/login")
    end
  end

  def update_password(conn, %{"password" => password_params}) do
    user = conn.assigns.current_user

    case Accounts.update_user_password(
           user.id,
           Map.get(password_params, "current_password"),
           Map.get(password_params, "password"),
           Map.get(password_params, "password_confirmation")
         ) do
      {:ok, _updated_user} ->
        conn
        |> put_flash(:info, gettext("Password updated successfully."))
        |> redirect(to: "/settings")

      {:error, :business_rule, %{rule: :invalid_current_password}} ->
        conn
        |> put_flash(:error, gettext("Current password is incorrect."))
        |> redirect(to: "/settings")

      {:error, :validation, changeset: changeset} ->
        conn
        |> put_flash(:error, first_changeset_error(changeset))
        |> redirect(to: "/settings")

      {:error, :not_found} ->
        conn
        |> put_flash(:error, gettext("User not found."))
        |> redirect(to: "/login")
    end
  end

  defp first_changeset_error(changeset) do
    {_field, {message, opts}} = List.first(changeset.errors) || {:base, {"Invalid data", []}}
    ErrorHelpers.translate_error({message, opts})
  end
end
