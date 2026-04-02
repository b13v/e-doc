defmodule EdocApi.Core.TenantMembership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(owner admin member)
  @statuses ~w(invited active removed)

  schema "tenant_memberships" do
    field :role, :string, default: "member"
    field :status, :string, default: "active"

    belongs_to :company, EdocApi.Core.Company
    belongs_to :user, EdocApi.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:company_id, :user_id, :role, :status])
    |> validate_required([:company_id, :user_id, :role, :status])
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:company_id, :user_id],
      name: :tenant_memberships_company_id_user_id_index
    )
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:user_id)
  end
end
