defmodule EdocApi.Repo.Migrations.AddPlatformAdminToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:is_platform_admin, :boolean, null: false, default: false)
    end

    create(index(:users, [:is_platform_admin]))
  end
end
