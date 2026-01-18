defmodule EdocApi.Repo.Migrations.AddContractIdToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add(:contract_id, references(:contracts, type: :binary_id, on_delete: :nilify_all))
    end

    create(index(:invoices, [:contract_id]))
  end
end
