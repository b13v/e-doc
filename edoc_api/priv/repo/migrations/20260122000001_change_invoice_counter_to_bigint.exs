defmodule EdocApi.Repo.Migrations.ChangeInvoiceCounterToBigint do
  use Ecto.Migration

  def up do
    alter table(:invoice_counters, primary_key: false) do
      modify(:next_seq, :bigint, null: false, default: 1)
    end
  end

  def down do
    alter table(:invoice_counters, primary_key: false) do
      modify(:next_seq, :integer, null: false, default: 1)
    end
  end
end
