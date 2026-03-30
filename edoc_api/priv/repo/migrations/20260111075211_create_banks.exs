defmodule EdocApi.Repo.Migrations.CreateBanks do
  use Ecto.Migration

  def change do
    create table(:banks, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:name, :string, null: false)
      # БИК / SWIFT
      add(:bic, :string, null: false)
      timestamps(type: :utc_datetime)
    end

    create(unique_index(:banks, [:bic]))
  end
end
