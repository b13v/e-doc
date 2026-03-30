defmodule EdocApi.Repo.Migrations.CreateInvoiceRecycledNumbers do
  use Ecto.Migration

  def change do
    create table(:invoice_recycled_numbers, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:number, :string, null: false)
      add(:sequence_name, :string, null: false, default: "default")
      add(:deleted_at, :utc_datetime)

      add(:company_id, references(:companies, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      timestamps(type: :utc_datetime)
    end

    # Create composite unique index to prevent duplicate recycled numbers per company/sequence
    create(
      unique_index(:invoice_recycled_numbers, [:company_id, :sequence_name, :number],
        name: :invoice_recycled_numbers_company_seq_num_index
      )
    )

    # Create index for fast lookup of oldest recycled numbers per company
    create(index(:invoice_recycled_numbers, [:company_id, :sequence_name, :inserted_at]))
  end
end
