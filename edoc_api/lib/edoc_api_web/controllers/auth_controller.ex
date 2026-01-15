defmodule EdocApiWeb.AuthController do
  use EdocApiWeb, :controller

  alias EdocApi.Accounts
  alias EdocApi.Auth.Token
  alias EdocApiWeb.Serializers.ErrorSerializer

  def signup(conn, params) do
    with {:ok, user} <- Accounts.register_user(params),
         {:ok, token, _claims} <- Token.generate_access_token(user.id) do
      json(conn, %{
        user: %{id: user.id, email: user.email},
        access_token: token
      })
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "validation_error", details: ErrorSerializer.errors_to_map(changeset)})

      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "signup_failed", reason: inspect(reason)})
    end
  end

  def login(conn, %{"email" => email, "password" => password}) do
    with {:ok, user} <- Accounts.authenticate_user(email, password),
         {:ok, token, _claims} <- Token.generate_access_token(user.id) do
      json(conn, %{
        user: %{id: user.id, email: user.email},
        access_token: token
      })
    else
      {:error, :invalid_credentials} ->
        conn
        |> put_status(:unauthorized)
        |> json(%{error: "invalid_credentials"})

      _ ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{error: "login_failed"})
    end
  end
end
