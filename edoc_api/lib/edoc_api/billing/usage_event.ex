defmodule EdocApi.Billing.UsageEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @metrics ~w(billable_documents)
  @resource_types ~w(invoice contract act)

  schema "usage_events" do
    field(:metric, :string)
    field(:resource_type, :string)
    field(:resource_id, :binary_id)
    field(:count, :integer, default: 1)
    field(:occurred_at, :utc_datetime)
    field(:period_start, :utc_datetime)
    field(:period_end, :utc_datetime)

    belongs_to(:company, EdocApi.Core.Company)

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :company_id,
      :metric,
      :resource_type,
      :resource_id,
      :count,
      :occurred_at,
      :period_start,
      :period_end
    ])
    |> put_default_occurred_at()
    |> validate_required([
      :company_id,
      :metric,
      :resource_type,
      :resource_id,
      :count,
      :occurred_at,
      :period_start,
      :period_end
    ])
    |> validate_inclusion(:metric, @metrics)
    |> validate_inclusion(:resource_type, @resource_types)
    |> validate_number(:count, greater_than: 0)
    |> validate_period()
    |> foreign_key_constraint(:company_id)
  end

  defp put_default_occurred_at(changeset) do
    case get_field(changeset, :occurred_at) do
      nil -> put_change(changeset, :occurred_at, DateTime.utc_now() |> DateTime.truncate(:second))
      _occurred_at -> changeset
    end
  end

  defp validate_period(changeset) do
    start_at = get_field(changeset, :period_start)
    end_at = get_field(changeset, :period_end)

    if start_at && end_at && DateTime.compare(end_at, start_at) != :gt do
      add_error(changeset, :period_end, "must be after start")
    else
      changeset
    end
  end
end
