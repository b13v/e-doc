defmodule EdocApiWeb.Plugs.AuthenticateSession do
  import Plug.Conn
  import Phoenix.Controller

  alias EdocApi.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    with user_id when not is_nil(user_id) <- get_session(conn, :user_id),
         user when not is_nil(user) <- Accounts.get_user(user_id) do
      assign(conn, :current_user, user)
    else
      _ -> redirect_to_login(conn)
    end
  end

  defp redirect_to_login(conn) do
    conn
    |> redirect(to: "/login")
    |> halt()
  end
end
