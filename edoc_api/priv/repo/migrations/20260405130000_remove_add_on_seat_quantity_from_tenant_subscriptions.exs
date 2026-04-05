defmodule EdocApi.Repo.Migrations.RemoveAddOnSeatQuantityFromTenantSubscriptions do
  use Ecto.Migration

  def change do
    alter table(:tenant_subscriptions) do
      remove :add_on_seat_quantity, :integer, null: false, default: 0
    end
  end
end
