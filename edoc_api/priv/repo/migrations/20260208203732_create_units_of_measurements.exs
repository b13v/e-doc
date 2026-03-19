defmodule EdocApi.Repo.Migrations.CreateUnitsOfMeasurements do
  use Ecto.Migration

  def change do
    create table(:units_of_measurements, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:okei_code, :integer, null: false)
      add(:symbol, :string, null: false)
      add(:name, :string, null: false)
      add(:category, :string)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:units_of_measurements, [:symbol]))
    create(index(:units_of_measurements, [:okei_code]))
  end
end
