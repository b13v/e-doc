defmodule EdocApi.Repo.Migrations.CreateInvoiceBankSnapshots do
  use Ecto.Migration

  def change do
    create table(:invoice_bank_snapshots, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:invoice_id, references(:invoices, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:bank_name, :string, null: false)
      add(:bic, :string, null: false)
      add(:iban, :string, null: false)
      add(:kbe, :string, null: false)
      add(:knp, :string, null: false)

      timestamps(type: :utc_datetime)
    end

    create(unique_index(:invoice_bank_snapshots, [:invoice_id]))
  end
end
