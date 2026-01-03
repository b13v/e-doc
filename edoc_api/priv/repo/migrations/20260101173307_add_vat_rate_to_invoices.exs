defmodule EdocApi.Repo.Migrations.AddVatRateToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add(:vat_rate, :integer, null: false, default: 0)
    end
  end
end
