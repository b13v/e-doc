defmodule EdocApi.Repo.Migrations.CreateInvoiceCounters do
  use Ecto.Migration

  def change do
    create table(:invoice_counters, primary_key: false) do
      add(
        :company_id,
        references(:companies, type: :binary_id, on_delete: :delete_all),
        primary_key: true
      )

      add(:next_seq, :integer, null: false, default: 1)

      timestamps(type: :utc_datetime)
    end
  end
end
