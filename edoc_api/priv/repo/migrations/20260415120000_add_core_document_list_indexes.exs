defmodule EdocApi.Repo.Migrations.AddCoreDocumentListIndexes do
  use Ecto.Migration

  def change do
    create(index(:invoices, [:company_id, :inserted_at]))
    create(index(:acts, [:company_id, :inserted_at]))
    create(index(:contracts, [:company_id, :inserted_at]))

    create(index(:invoices, [:company_id, :status]))
    create(index(:acts, [:company_id, :status]))
  end
end
