defmodule EdocApi.DocumentDelivery.Delivery do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @document_types ~w(invoice act contract)
  @channels ~w(email whatsapp telegram)
  @kinds ~w(official share)
  @statuses ~w(pending sent opened failed)

  schema "document_deliveries" do
    field(:document_type, :string)
    field(:document_id, :binary_id)
    field(:channel, :string)
    field(:kind, :string)
    field(:status, :string)
    field(:recipient_email, :string)
    field(:recipient_phone, :string)
    field(:recipient_name, :string)
    field(:sent_at, :utc_datetime)
    field(:opened_at, :utc_datetime)
    field(:error_message, :string)
    field(:metadata, :map, default: %{})

    belongs_to(:public_access_token, EdocApi.DocumentDelivery.PublicAccessToken)

    timestamps(type: :utc_datetime)
  end

  def changeset(delivery, attrs) do
    delivery
    |> cast(attrs, [
      :document_type,
      :document_id,
      :channel,
      :kind,
      :status,
      :recipient_email,
      :recipient_phone,
      :recipient_name,
      :sent_at,
      :opened_at,
      :error_message,
      :metadata,
      :public_access_token_id
    ])
    |> validate_required([:document_type, :document_id, :channel, :kind, :status])
    |> validate_inclusion(:document_type, @document_types)
    |> validate_inclusion(:channel, @channels)
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:status, @statuses)
    |> foreign_key_constraint(:public_access_token_id)
  end
end
