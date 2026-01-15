defmodule EdocApi.Repo.Migrations.RenameCompanyBankToBankName do
  use Ecto.Migration

  def change do
    rename(table(:companies), :bank, to: :bank_name)
  end
end
