defmodule EdocApi.Repo.Migrations.CreateBuyerBankAccounts do
  use Ecto.Migration

  def change do
    create table(:buyer_bank_accounts, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:buyer_id, references(:buyers, type: :binary_id, on_delete: :delete_all), null: false)
      add(:bank_id, references(:banks, type: :binary_id, on_delete: :restrict), null: false)
      add(:iban, :string)
      add(:bic, :string)
      add(:is_default, :boolean, default: false, null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:buyer_bank_accounts, [:buyer_id]))
    create(index(:buyer_bank_accounts, [:bank_id]))
    create(unique_index(:buyer_bank_accounts, [:buyer_id, :iban], where: "iban IS NOT NULL"))

    create(
      unique_index(:buyer_bank_accounts, [:buyer_id],
        where: "is_default = true",
        name: :buyer_bank_accounts_single_default
      )
    )
  end
end
