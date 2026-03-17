defmodule EdocApi.Repo.Migrations.CreateActs do
  use Ecto.Migration

  def change do
    create table(:acts, primary_key: false) do
      add(:id, :binary_id, primary_key: true)
      add(:number, :string, null: false)
      add(:status, :string, null: false, default: "draft")
      add(:issue_date, :date, null: false)
      add(:due_date, :date, null: false)
      add(:actual_date, :date)
      add(:currency, :string, null: false, default: "KZT")
      add(:vat_rate, :integer, null: false, default: 16)

      add(:seller_name, :string, null: false)
      add(:seller_bin_iin, :string, null: false)
      add(:seller_address, :string, null: false)
      add(:seller_phone, :string)

      add(:buyer_name, :string, null: false)
      add(:buyer_bin_iin, :string, null: false)
      add(:buyer_address, :string, null: false)
      add(:buyer_phone, :string)

      add(:company_id, references(:companies, type: :binary_id, on_delete: :nothing), null: false)
      add(:user_id, references(:users, type: :binary_id, on_delete: :nothing), null: false)
      add(:buyer_id, references(:buyers, type: :binary_id, on_delete: :nothing), null: false)
      add(:contract_id, references(:contracts, type: :binary_id, on_delete: :nothing))

      timestamps(type: :utc_datetime)
    end

    create(index(:acts, [:company_id]))
    create(index(:acts, [:user_id]))
    create(index(:acts, [:buyer_id]))
    create(index(:acts, [:contract_id]))
    create(index(:acts, [:status]))
    create(unique_index(:acts, [:company_id, :number]))
  end
end
