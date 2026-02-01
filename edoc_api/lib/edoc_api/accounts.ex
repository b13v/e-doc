defmodule EdocApi.Accounts do
  import Ecto.Query, warn: false
  alias EdocApi.Repo
  alias EdocApi.Accounts.User
  alias EdocApi.Errors

  def get_user(id) when is_binary(id), do: Repo.get(User, id)
  def get_user(_), do: nil

  def get_user_by_email(email) when is_binary(email) do
    email = email |> String.trim() |> String.downcase()
    Repo.get_by(User, email: email)
  end

  def register_user(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
    |> Errors.from_changeset()
  end

  def authenticate_user(email, password) do
    case get_user_by_email(email) do
      nil ->
        Argon2.no_user_verify()
        Errors.business_rule(:invalid_credentials, %{email: email})

      user ->
        if Argon2.verify_pass(password, user.password_hash) do
          {:ok, user}
        else
          Errors.business_rule(:invalid_credentials, %{email: email})
        end
    end
  end
end
