defmodule EdocApiWeb.Plugs.Authenticate do
  import Plug.Conn

  alias EdocApi.Auth.Token
  alias EdocApi.Accounts
  alias EdocApiWeb.ErrorMapper

  def init(opts), do: opts

  def call(conn, _opts) do
    with token when is_binary(token) <- get_bearer_token(conn),
         {:ok, claims} <- Token.verify(token),
         user_id when is_binary(user_id) <- claims["sub"],
         user when not is_nil(user) <- Accounts.get_user(user_id) do
      if user.verified_at != nil do
        assign(conn, :current_user, user)
      else
        conn
        |> ErrorMapper.unauthorized("email_not_verified", %{
          message: "Please verify your email before accessing this resource"
        })
        |> halt()
      end
    else
      _ ->
        conn
        |> ErrorMapper.unauthorized()
        |> halt()
    end
  end

  defp get_bearer_token(conn) do
    conn
    |> get_req_header("authorization")
    |> List.first()
    |> case do
      "Bearer " <> token -> token
      _ -> nil
    end
  end
end
