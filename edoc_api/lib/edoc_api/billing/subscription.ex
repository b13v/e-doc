defmodule EdocApi.Billing.Subscription do
  use Ecto.Schema
  import Ecto.Changeset

  alias EdocApi.Billing.{Plan, SubscriptionStatus}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @auto_renew_modes ~w(manual kaspi_link disabled)

  schema "subscriptions" do
    field(:status, :string, default: SubscriptionStatus.trialing())
    field(:current_period_start, :utc_datetime)
    field(:current_period_end, :utc_datetime)
    field(:grace_until, :utc_datetime)
    field(:extra_user_seats, :integer, default: 0)
    field(:auto_renew_mode, :string, default: "manual")
    field(:change_effective_at, :utc_datetime)
    field(:blocked_reason, :string)

    belongs_to(:company, EdocApi.Core.Company)
    belongs_to(:plan, Plan)
    belongs_to(:next_plan, Plan)

    timestamps(type: :utc_datetime)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :company_id,
      :plan_id,
      :status,
      :current_period_start,
      :current_period_end,
      :grace_until,
      :extra_user_seats,
      :auto_renew_mode,
      :next_plan_id,
      :change_effective_at,
      :blocked_reason
    ])
    |> validate_required([
      :company_id,
      :plan_id,
      :status,
      :current_period_start,
      :current_period_end,
      :auto_renew_mode
    ])
    |> validate_inclusion(:status, SubscriptionStatus.all())
    |> validate_inclusion(:auto_renew_mode, @auto_renew_modes)
    |> validate_number(:extra_user_seats, greater_than_or_equal_to: 0)
    |> validate_period(:current_period_start, :current_period_end)
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:plan_id)
    |> foreign_key_constraint(:next_plan_id)
    |> unique_constraint(:company_id, name: :subscriptions_one_current_per_company_index)
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
