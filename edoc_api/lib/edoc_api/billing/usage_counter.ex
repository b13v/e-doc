defmodule EdocApi.Billing.UsageCounter do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @metrics ~w(billable_documents)

  schema "usage_counters" do
    field(:metric, :string)
    field(:period_start, :utc_datetime)
    field(:period_end, :utc_datetime)
    field(:value, :integer, default: 0)

    belongs_to(:company, EdocApi.Core.Company)

    timestamps(type: :utc_datetime)
  end

  def changeset(counter, attrs) do
    counter
    |> cast(attrs, [:company_id, :metric, :period_start, :period_end, :value])
    |> validate_required([:company_id, :metric, :period_start, :period_end, :value])
    |> validate_inclusion(:metric, @metrics)
    |> validate_number(:value, greater_than_or_equal_to: 0)
    |> validate_period(:period_start, :period_end)
    |> foreign_key_constraint(:company_id)
    |> unique_constraint([:company_id, :metric, :period_start, :period_end],
      name: :usage_counters_company_metric_period_index
    )
  end

  defp validate_period(changeset, start_field, end_field) do
    start_at = get_field(changeset, start_field)
    end_at = get_field(changeset, end_field)

    if start_at && end_at && DateTime.compare(end_at, start_at) != :gt do
      add_error(changeset, end_field, "must be after start")
    else
      changeset
    end
  end
end
