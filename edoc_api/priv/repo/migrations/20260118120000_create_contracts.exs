defmodule EdocApi.Repo.Migrations.CreateContracts do
  use Ecto.Migration

  def change do
    create table(:contracts, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :company_id,
        references(:companies, type: :binary_id, on_delete: :nothing),
        null: false
      )

      add(:number, :string, null: false)
      add(:date, :date, null: false)
      add(:title, :string)

      timestamps(type: :utc_datetime)
    end

    create(index(:contracts, [:company_id]))
    create(unique_index(:contracts, [:company_id, :number]))
  end
end
