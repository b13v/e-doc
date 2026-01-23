defmodule EdocApi.Repo.Migrations.EnsureSingleDefaultBankAccount do
  use Ecto.Migration

  def change do
    create(
      unique_index(:company_bank_accounts, [:company_id],
        name: :company_bank_accounts_single_default,
        where: "is_default = true"
      )
    )
  end
end
