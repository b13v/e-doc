defmodule EdocApi.Repo.Migrations.AddPerformanceIndexes do
  use Ecto.Migration

  def change do
    create(index(:invoices, [:status]))
    create(index(:contracts, [:status]))
    create(index(:contracts, [:company_id, :status]))
    create(index(:invoices, [:user_id, :inserted_at]))
  end
end
