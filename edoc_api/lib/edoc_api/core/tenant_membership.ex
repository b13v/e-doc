defmodule EdocApi.Core.TenantMembership do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @roles ~w(owner admin member)
  @statuses ~w(invited pending_seat active removed)

  schema "tenant_memberships" do
    field :role, :string, default: "member"
    field :status, :string, default: "active"
    field :invite_email, :string

    belongs_to :company, EdocApi.Core.Company
    belongs_to :user, EdocApi.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(membership, attrs) do
    membership
    |> cast(attrs, [:company_id, :user_id, :role, :status, :invite_email])
    |> validate_required([:company_id, :role, :status])
    |> validate_inclusion(:role, @roles)
    |> validate_inclusion(:status, @statuses)
    |> validate_status_fields()
    |> unique_constraint([:company_id, :user_id],
      name: :tenant_memberships_company_id_user_id_index
    )
    |> unique_constraint([:company_id, :invite_email],
      name: :tenant_memberships_company_id_invite_email_index
    )
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:user_id)
  end

  defp validate_status_fields(changeset) do
    case get_field(changeset, :status) do
      status when status in ["invited", "pending_seat"] ->
        changeset
        |> validate_required([:invite_email])

      "active" ->
        changeset
        |> validate_required([:user_id])

      _ ->
        changeset
    end
  end
end
