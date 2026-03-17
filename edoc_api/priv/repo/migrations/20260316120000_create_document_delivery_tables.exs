defmodule EdocApi.Repo.Migrations.CreateDocumentDeliveryTables do
  use Ecto.Migration

  def change do
    create table(:public_access_tokens, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:token_hash, :string, null: false)
      add(:document_type, :string, null: false)
      add(:document_id, :binary_id, null: false)
      add(:expires_at, :utc_datetime, null: false)
      add(:revoked_at, :utc_datetime)
      add(:last_accessed_at, :utc_datetime)

      add(
        :created_by_user_id,
        references(:users, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:public_access_tokens, [:token_hash]))
    create(index(:public_access_tokens, [:document_type, :document_id]))
    create(index(:public_access_tokens, [:created_by_user_id]))
    create(index(:public_access_tokens, [:expires_at]))

    create(
      constraint(:public_access_tokens, :public_access_tokens_document_type_check,
        check: "document_type IN ('invoice', 'act', 'contract')"
      )
    )

    create table(:document_deliveries, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:document_type, :string, null: false)
      add(:document_id, :binary_id, null: false)
      add(:channel, :string, null: false)
      add(:kind, :string, null: false)
      add(:status, :string, null: false)
      add(:recipient_email, :string)
      add(:recipient_phone, :string)
      add(:recipient_name, :string)
      add(:sent_at, :utc_datetime)
      add(:opened_at, :utc_datetime)
      add(:error_message, :text)
      add(:metadata, :map, default: %{}, null: false)

      add(
        :public_access_token_id,
        references(:public_access_tokens, type: :binary_id, on_delete: :nilify_all)
      )

      timestamps(type: :utc_datetime)
    end

    create(index(:document_deliveries, [:document_type, :document_id]))
    create(index(:document_deliveries, [:channel, :status]))
    create(index(:document_deliveries, [:public_access_token_id]))

    create(
      index(:document_deliveries, [:recipient_email],
        where: "recipient_email IS NOT NULL",
        name: :document_deliveries_recipient_email_idx
      )
    )

    create(
      constraint(:document_deliveries, :document_deliveries_document_type_check,
        check: "document_type IN ('invoice', 'act', 'contract')"
      )
    )

    create(
      constraint(:document_deliveries, :document_deliveries_channel_check,
        check: "channel IN ('email', 'whatsapp', 'telegram')"
      )
    )

    create(
      constraint(:document_deliveries, :document_deliveries_kind_check,
        check: "kind IN ('official', 'share')"
      )
    )

    create(
      constraint(:document_deliveries, :document_deliveries_status_check,
        check: "status IN ('pending', 'sent', 'opened', 'failed')"
      )
    )
  end
end
