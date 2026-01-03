defmodule EdocApi.Repo.Migrations.CreateInvoices do
  use Ecto.Migration

  def change do
    create table(:invoices, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:number, :string)
      add(:service_name, :string)
      add(:issue_date, :date)
      add(:due_date, :date)
      add(:currency, :string)
      add(:seller_name, :string)
      add(:seller_bin_iin, :string)
      add(:seller_address, :string)
      add(:seller_iban, :string)
      add(:buyer_name, :string)
      add(:buyer_bin_iin, :string)
      add(:buyer_address, :string)
      add(:subtotal, :decimal)
      add(:vat, :decimal)
      add(:total, :decimal)
      add(:status, :string)

      add(
        :company_id,
        references(:companies, type: :binary_id, on_delete: :nothing)
      )

      add(:user_id, references(:users, type: :binary_id, on_delete: :nothing))

      timestamps(type: :utc_datetime)
    end

    create(index(:invoices, [:user_id]))
    create(index(:invoices, [:company_id]))
    create(unique_index(:invoices, [:user_id, :number]))
  end
end
