defmodule EdocApi.Repo.Migrations.AddVerifiedAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:verified_at, :utc_datetime)
    end
  end
end
