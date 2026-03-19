defmodule EdocApiWeb.PageController do
  use EdocApiWeb, :controller

  alias EdocApi.Accounts

  def home(conn, _params) do
    case current_verified_user(conn) do
      nil ->
        conn
        |> put_resp_header("content-type", "text/html; charset=utf-8")
        |> send_file(200, landing_page_path())

      _user ->
        redirect(conn, to: "/invoices")
    end
  end

  defp current_verified_user(conn) do
    case get_session(conn, :user_id) do
      nil ->
        nil

      user_id ->
        case Accounts.get_user(user_id) do
          %{verified_at: verified_at} = user when not is_nil(verified_at) -> user
          _ -> nil
        end
    end
  end

  defp landing_page_path do
    Path.expand("../../../index.html", __DIR__)
  end
end
