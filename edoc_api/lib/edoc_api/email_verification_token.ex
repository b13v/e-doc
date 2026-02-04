defmodule EdocApi.EmailVerificationToken do
  @moduledoc """
  Schema for email verification tokens.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "email_verification_tokens" do
    field(:token_hash, :string)
    field(:expires_at, :utc_datetime)
    field(:used_at, :utc_datetime)

    belongs_to(:user, EdocApi.Accounts.User)

    timestamps(type: :utc_datetime)
  end

  @doc """
  Creates a changeset for a verification token.
  """
  def changeset(token, attrs) do
    token
    |> cast(attrs, [:user_id, :token_hash, :expires_at, :used_at])
    |> validate_required([:user_id, :token_hash, :expires_at])
    |> validate_expiry(:expires_at)
    |> foreign_key_constraint(:user_id)
  end

  defp validate_expiry(changeset, field) do
    case get_field(changeset, field) do
      nil -> changeset
      %DateTime{} = expiry -> add_expiry_error_if_past(changeset, field, expiry)
    end
  end

  defp add_expiry_error_if_past(changeset, field, expiry) do
    if DateTime.compare(expiry, DateTime.utc_now()) == :lt do
      add_error(changeset, field, "has already expired")
    else
      changeset
    end
  end
end
