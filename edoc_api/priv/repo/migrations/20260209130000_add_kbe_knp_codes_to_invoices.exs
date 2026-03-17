defmodule EdocApi.Repo.Migrations.AddKbeKnpCodesToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add(:kbe_code_id, references(:kbe_codes, type: :binary_id, on_delete: :restrict))
      add(:knp_code_id, references(:knp_codes, type: :binary_id, on_delete: :restrict))
    end

    create(index(:invoices, [:kbe_code_id]))
    create(index(:invoices, [:knp_code_id]))
  end
end
