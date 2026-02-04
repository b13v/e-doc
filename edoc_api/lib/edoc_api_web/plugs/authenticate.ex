defmodule EdocApiWeb.Plugs.Authenticate do
  import Plug.Conn

  alias EdocApi.Auth.Token
  alias EdocApi.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    with token when is_binary(token) <- get_bearer_token(conn),
         {:ok, claims} <- Token.verify(token),
         user_id when is_binary(user_id) <- claims["sub"],
         user when not is_nil(user) <- Accounts.get_user(user_id) do
      if user.verified_at != nil do
        assign(conn, :current_user, user)
      else
        unauthorized_with_message(
          conn,
          "email_not_verified",
          "Please verify your email before accessing this resource"
        )
      end
    else
      _ -> unauthorized(conn)
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

  defp unauthorized(conn) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, ~s({"error":"unauthorized"}))
    |> halt()
  end

  defp unauthorized_with_message(conn, code, message) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(401, Jason.encode!(%{error: code, message: message}))
    |> halt()
  end
end
