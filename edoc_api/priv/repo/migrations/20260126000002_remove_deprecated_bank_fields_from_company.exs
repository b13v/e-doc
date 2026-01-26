defmodule EdocApi.Repo.Migrations.RemoveDeprecatedBankFieldsFromCompany do
  use Ecto.Migration

  def up do
    # Step 1: Ensure all companies with deprecated bank fields have a corresponding bank account
    execute("""
    INSERT INTO company_bank_accounts (id, company_id, label, iban, bank_id, kbe_code_id, knp_code_id, is_default, inserted_at, updated_at)
    SELECT
      gen_random_uuid() as id,
      companies.id as company_id,
      'Main Account' as label,
      companies.iban as iban,
      companies.bank_id as bank_id,
      companies.kbe_code_id as kbe_code_id,
      companies.knp_code_id as knp_code_id,
      true as is_default,
      NOW() as inserted_at,
      NOW() as updated_at
    FROM companies
    WHERE companies.iban IS NOT NULL
      AND NOT EXISTS (
        SELECT 1 FROM company_bank_accounts
        WHERE company_bank_accounts.company_id = companies.id
      )
    """)

    # Step 2: Remove deprecated columns
    alter table(:companies) do
      remove(:bank_name, :string)
      remove(:iban, :string)
      remove(:bank_id, :binary_id)
      remove(:kbe_code_id, :binary_id)
      remove(:knp_code_id, :binary_id)
    end
  end

  def down do
    # Add back the deprecated columns (for rollback)
    alter table(:companies) do
      add(:bank_name, :string)
      add(:iban, :string)
      add(:bank_id, :binary_id)
      add(:kbe_code_id, :binary_id)
      add(:knp_code_id, :binary_id)
    end
  end
end
