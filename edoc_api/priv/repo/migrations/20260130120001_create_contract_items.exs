defmodule EdocApi.Repo.Migrations.CreateContractItems do
  use Ecto.Migration

  def change do
    create table(:contract_items, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(
        :contract_id,
        references(:contracts, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:name, :string, null: false)
      add(:qty, :decimal, null: false)
      add(:unit_price, :decimal, null: false)
      add(:amount, :decimal, null: false)
      add(:code, :string)

      timestamps(type: :utc_datetime)
    end

    create(index(:contract_items, [:contract_id]))
  end
end
