defmodule EdocApi.Repo.Migrations.AddBankAccountIdToInvoices do
  use Ecto.Migration

  def change do
    alter table(:invoices) do
      add(
        :bank_account_id,
        references(:company_bank_accounts, type: :binary_id, on_delete: :nilify_all)
      )
    end

    create(index(:invoices, [:bank_account_id]))
  end
end
