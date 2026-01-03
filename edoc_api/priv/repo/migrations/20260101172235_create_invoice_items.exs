defmodule EdocApi.Repo.Migrations.CreateInvoiceItems do
  use Ecto.Migration

  def change do
    create table(:invoice_items, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:invoice_id, references(:invoices, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:code, :string)
      add(:name, :string, null: false)
      add(:qty, :integer, null: false, default: 1)
      add(:unit_price, :decimal, null: false)
      add(:amount, :decimal, null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:invoice_items, [:invoice_id]))
  end
end
