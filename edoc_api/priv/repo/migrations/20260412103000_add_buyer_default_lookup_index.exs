defmodule EdocApi.Repo.Migrations.AddBuyerDefaultLookupIndex do
  use Ecto.Migration

  def change do
    create(
      index(:buyer_bank_accounts, [:buyer_id, :is_default, :inserted_at],
        name: :buyer_bank_accounts_default_lookup_index
      )
    )
  end
end
