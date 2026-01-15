defmodule EdocApi.Repo.Migrations.CreateKbeCodes do
  use Ecto.Migration

  def change do
    create table(:kbe_codes, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      # напр "17"
      add(:code, :string, null: false)
      add(:description, :string)
      timestamps(type: :utc_datetime)
    end

    create(unique_index(:kbe_codes, [:code]))
  end
end
