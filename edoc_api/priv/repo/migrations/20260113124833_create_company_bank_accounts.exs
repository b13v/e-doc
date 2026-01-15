defmodule EdocApi.Repo.Migrations.CreateCompanyBankAccounts do
  use Ecto.Migration

  def change do
    create table(:company_bank_accounts, primary_key: false) do
      add(:id, :binary_id, primary_key: true)

      add(:company_id, references(:companies, type: :binary_id, on_delete: :delete_all),
        null: false
      )

      add(:label, :string, null: false)
      add(:iban, :string, null: false)

      add(:bank_id, references(:banks, type: :binary_id, on_delete: :restrict), null: false)

      add(:kbe_code_id, references(:kbe_codes, type: :binary_id, on_delete: :restrict),
        null: false
      )

      add(:knp_code_id, references(:knp_codes, type: :binary_id, on_delete: :restrict),
        null: false
      )

      add(:is_default, :boolean, default: false, null: false)

      timestamps(type: :utc_datetime)
    end

    create(index(:company_bank_accounts, [:company_id]))
    create(index(:company_bank_accounts, [:bank_id]))
    create(index(:company_bank_accounts, [:kbe_code_id]))
    create(index(:company_bank_accounts, [:knp_code_id]))

    create(unique_index(:company_bank_accounts, [:company_id, :iban]))
  end
end
