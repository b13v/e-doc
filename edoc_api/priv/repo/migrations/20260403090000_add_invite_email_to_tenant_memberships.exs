defmodule EdocApi.Repo.Migrations.AddInviteEmailToTenantMemberships do
  use Ecto.Migration

  def change do
    drop constraint(:tenant_memberships, "tenant_memberships_user_id_fkey")

    alter table(:tenant_memberships) do
      add :invite_email, :string
      modify :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: true
    end

    create unique_index(:tenant_memberships, [:company_id, :invite_email],
             where: "invite_email IS NOT NULL"
           )
  end
end
