defmodule EdocApi.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias EdocApi.Validators.Email

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field(:email, :string)
    field(:password, :string, virtual: true)
    field(:password_hash, :string)
    field(:verified_at, :utc_datetime)

    has_one(:company, EdocApi.Core.Company)

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset used ONLY for user registration"
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password])
    |> update_change(:email, &Email.normalize/1)
    |> validate_required([:email, :password])
    |> Email.validate_required(:email)
    |> validate_length(:password, min: 8, max: 72)
    |> unique_constraint(:email)
    |> put_password_hash()
  end

  defp put_password_hash(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> put_change(changeset, :password_hash, Argon2.hash_pwd_salt(password))
    end
  end
end
