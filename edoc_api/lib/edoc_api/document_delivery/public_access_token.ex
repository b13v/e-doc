defmodule EdocApi.DocumentDelivery.PublicAccessToken do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @document_types ~w(invoice act contract)

  schema "public_access_tokens" do
    field(:token_hash, :string)
    field(:document_type, :string)
    field(:document_id, :binary_id)
    field(:expires_at, :utc_datetime)
    field(:revoked_at, :utc_datetime)
    field(:last_accessed_at, :utc_datetime)

    belongs_to(:created_by_user, EdocApi.Accounts.User)
    has_many(:deliveries, EdocApi.DocumentDelivery.Delivery)

    timestamps(type: :utc_datetime)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [
      :token_hash,
      :document_type,
      :document_id,
      :expires_at,
      :revoked_at,
      :last_accessed_at,
      :created_by_user_id
    ])
    |> validate_required([
      :token_hash,
      :document_type,
      :document_id,
      :expires_at,
      :created_by_user_id
    ])
    |> validate_inclusion(:document_type, @document_types)
    |> validate_expiry(:expires_at)
    |> unique_constraint(:token_hash)
    |> foreign_key_constraint(:created_by_user_id)
  end

  defp validate_expiry(changeset, field) do
    case get_field(changeset, field) do
      %DateTime{} = expires_at ->
        if DateTime.compare(expires_at, DateTime.utc_now()) == :gt do
          changeset
        else
          add_error(changeset, field, "must be in the future")
        end

      _ ->
        changeset
    end
  end
end
