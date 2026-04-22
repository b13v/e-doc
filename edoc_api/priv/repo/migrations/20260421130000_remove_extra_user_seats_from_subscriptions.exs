defmodule EdocApi.Repo.Migrations.RemoveExtraUserSeatsFromSubscriptions do
  use Ecto.Migration

  def change do
    alter table(:subscriptions) do
      remove(:extra_user_seats, :integer, null: false, default: 0)
    end
  end
end
