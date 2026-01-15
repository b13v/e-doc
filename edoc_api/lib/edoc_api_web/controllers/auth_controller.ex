defmodule EdocApiWeb.AuthController do
  use EdocApiWeb, :controller

  alias EdocApi.Accounts
  alias EdocApi.Auth.Token
  alias EdocApiWeb.ErrorMapper

  def signup(conn, params) do
    with {:ok, user} <- Accounts.register_user(params),
         {:ok, token, _claims} <- Token.generate_access_token(user.id) do
      json(conn, %{
        user: %{id: user.id, email: user.email},
        access_token: token
      })
    else
      {:error, %Ecto.Changeset{} = changeset} ->
        ErrorMapper.validation(conn, changeset)

      {:error, reason} ->
        ErrorMapper.unprocessable(conn, "signup_failed", %{reason: inspect(reason)})
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
        ErrorMapper.unauthorized(conn, "invalid_credentials")

      _ ->
        ErrorMapper.unprocessable(conn, "login_failed")
    end
  end
end
