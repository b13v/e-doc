defmodule EdocApi.Repo.Migrations.CreateEmailVerificationTokens do
  use Ecto.Migration

  def change do
    create table(:email_verification_tokens, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false)
      add(:token_hash, :string, null: false)
      add(:expires_at, :utc_datetime, null: false)
      add(:used_at, :utc_datetime)

      timestamps(type: :utc_datetime)
    end

    create(index(:email_verification_tokens, [:user_id]))
    create(index(:email_verification_tokens, [:token_hash]))
    create(index(:email_verification_tokens, [:expires_at]))
  end
end
