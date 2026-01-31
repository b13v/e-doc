defmodule EdocApi.Repo.Migrations.AddContractEnhancements do
  use Ecto.Migration

  def change do
    alter table(:contracts) do
      # New fields from spec
      add(:city, :string)
      add(:currency, :string, default: "KZT")
      add(:vat_rate, :integer, default: 16)

      # Status: add signed_at for future extension
      add(:signed_at, :utc_datetime)

      # Buyer company reference (nullable for external counterparties)
      add(
        :buyer_company_id,
        references(:companies, type: :binary_id, on_delete: :nilify_all)
      )

      # Buyer details stored directly (for external counterparties not in system)
      add(:buyer_name, :string)
      add(:buyer_legal_form, :string)
      add(:buyer_bin_iin, :string)
      add(:buyer_address, :string)
      add(:buyer_director_name, :string)
      add(:buyer_director_title, :string)
      add(:buyer_basis, :string)
      add(:buyer_phone, :string)
      add(:buyer_email, :string)

      # Bank account reference for seller's bank details in contract
      add(
        :bank_account_id,
        references(:company_bank_accounts, type: :binary_id, on_delete: :nilify_all)
      )
    end

    # Rename date to issue_date for clarity
    execute("ALTER TABLE contracts RENAME COLUMN date TO issue_date")

    create(index(:contracts, [:buyer_company_id]))
    create(index(:contracts, [:bank_account_id]))
  end
end
