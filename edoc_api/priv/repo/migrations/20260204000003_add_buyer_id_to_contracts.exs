defmodule EdocApi.Repo.Migrations.AddBuyerIdToContracts do
  use Ecto.Migration

  def change do
    alter table(:contracts) do
      add(:buyer_id, references(:buyers, type: :binary_id, on_delete: :nothing))
    end

    create(index(:contracts, [:buyer_id]))
  end
end
