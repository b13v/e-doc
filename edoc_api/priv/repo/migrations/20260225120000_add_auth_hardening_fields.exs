defmodule EdocApi.Repo.Migrations.AddAuthHardeningFields do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:failed_login_attempts, :integer, default: 0, null: false)
      add(:locked_until, :utc_datetime)
    end

    create table(:refresh_tokens, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false)
      add(:token_hash, :string, null: false)
      add(:expires_at, :utc_datetime, null: false)
      add(:revoked_at, :utc_datetime)
      add(:replaced_by_id, :binary_id)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:refresh_tokens, [:token_hash]))
    create(index(:refresh_tokens, [:user_id]))
    create(index(:refresh_tokens, [:expires_at]))
  end
end
