defmodule EdocApi.Core.TenantUsageEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @event_types ~w(invoice_issued contract_issued act_issued)
  @document_types ~w(invoice contract act)

  schema "tenant_usage_events" do
    field :event_type, :string
    field :document_type, :string
    field :document_id, :binary_id
    field :occurred_at, :utc_datetime
    field :period_start, :utc_datetime
    field :period_end, :utc_datetime

    belongs_to :company, EdocApi.Core.Company

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :company_id,
      :event_type,
      :document_type,
      :document_id,
      :occurred_at,
      :period_start,
      :period_end
    ])
    |> validate_required([
      :company_id,
      :event_type,
      :document_type,
      :document_id,
      :occurred_at,
      :period_start,
      :period_end
    ])
    |> validate_inclusion(:event_type, @event_types)
    |> validate_inclusion(:document_type, @document_types)
    |> unique_constraint([:company_id, :document_type, :document_id],
      name: :tenant_usage_events_company_id_document_type_document_id_index
    )
    |> foreign_key_constraint(:company_id)
  end
end
