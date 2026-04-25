defmodule EdocApi.Repo.Migrations.AddBuyerSnapshotFieldsToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add(:buyer_city, :string)
      add(:buyer_legal_form, :string)
    end
  end
end
