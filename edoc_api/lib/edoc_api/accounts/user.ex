defmodule EdocApi.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  alias EdocApi.Validators.Email

  @legal_acceptance_version "2026-05-03"

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field(:email, :string)
    field(:first_name, :string)
    field(:last_name, :string)
    field(:password, :string, virtual: true)
    field(:password_hash, :string)
    field(:verified_at, :utc_datetime)
    field(:failed_login_attempts, :integer, default: 0)
    field(:locked_until, :utc_datetime)
    field(:is_platform_admin, :boolean, default: false)
    field(:legal_terms_accepted, :boolean, virtual: true)
    field(:terms_accepted_at, :utc_datetime)
    field(:privacy_accepted_at, :utc_datetime)
    field(:legal_acceptance_version, :string)

    has_one(:company, EdocApi.Core.Company)
    has_many(:refresh_tokens, EdocApi.Auth.RefreshToken)

    timestamps(type: :utc_datetime)
  end

  @doc "Changeset used ONLY for user registration"
  def registration_changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password, :legal_terms_accepted])
    |> update_change(:email, &Email.normalize/1)
    |> validate_required([:email, :password, :legal_terms_accepted])
    |> Email.validate_required(:email)
    |> validate_length(:password, min: 8, max: 72)
    |> validate_acceptance(:legal_terms_accepted,
      message: "must accept terms of use and privacy policy"
    )
    |> unique_constraint(:email)
    |> put_legal_acceptance()
    |> put_password_hash()
  end

  def legal_acceptance_version, do: @legal_acceptance_version

  def profile_changeset(user, attrs) do
    user
    |> cast(attrs, [:first_name, :last_name])
    |> update_change(:first_name, &normalize_name/1)
    |> update_change(:last_name, &normalize_name/1)
    |> validate_required([:first_name, :last_name])
    |> validate_length(:first_name, min: 2, max: 100)
    |> validate_length(:last_name, min: 2, max: 100)
  end

  def password_update_changeset(user, attrs) do
    user
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_confirmation(:password, required: true)
    |> validate_length(:password, min: 8, max: 72)
    |> put_password_hash()
  end

  defp normalize_name(value) when is_binary(value), do: String.trim(value)
  defp normalize_name(value), do: value

  defp put_password_hash(changeset) do
    case get_change(changeset, :password) do
      nil -> changeset
      password -> put_change(changeset, :password_hash, Argon2.hash_pwd_salt(password))
    end
  end

  defp put_legal_acceptance(changeset) do
    if get_field(changeset, :legal_terms_accepted) == true and changeset.valid? do
      accepted_at = DateTime.utc_now() |> DateTime.truncate(:second)

      changeset
      |> put_change(:terms_accepted_at, accepted_at)
      |> put_change(:privacy_accepted_at, accepted_at)
      |> put_change(:legal_acceptance_version, @legal_acceptance_version)
    else
      changeset
    end
  end
end
