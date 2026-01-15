defmodule EdocApi.Repo.Migrations.CreateKnpCodes do
  use Ecto.Migration

  def change do
    create table(:knp_codes, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      # напр "859"
      add(:code, :string, null: false)
      add(:description, :string)
      timestamps(type: :utc_datetime)
    end

    create(unique_index(:knp_codes, [:code]))
  end
end
