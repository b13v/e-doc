defmodule EdocApi.Core.TenantSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @plans ~w(trial starter basic)
  @statuses ~w(active canceled past_due)

  schema "tenant_subscriptions" do
    field :plan, :string
    field :status, :string, default: "active"
    field :period_start, :utc_datetime
    field :period_end, :utc_datetime
    field :included_document_limit, :integer, default: 10
    field :included_seat_limit, :integer, default: 2
    field :add_on_seat_quantity, :integer, default: 0
    field :trial_document_limit, :integer, default: 10
    field :trial_started_at, :utc_datetime
    field :trial_ended_at, :utc_datetime
    field :skip_trial, :boolean, default: false

    belongs_to :company, EdocApi.Core.Company

    timestamps(type: :utc_datetime)
  end

  def changeset(subscription, attrs) do
    subscription
    |> cast(attrs, [
      :company_id,
      :plan,
      :status,
      :period_start,
      :period_end,
      :included_document_limit,
      :included_seat_limit,
      :add_on_seat_quantity,
      :trial_document_limit,
      :trial_started_at,
      :trial_ended_at,
      :skip_trial
    ])
    |> validate_required([:company_id, :plan, :status, :period_start, :period_end])
    |> validate_inclusion(:plan, @plans)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:included_document_limit, greater_than: 0)
    |> validate_number(:included_seat_limit, greater_than: 0)
    |> validate_number(:trial_document_limit, greater_than: 0)
    |> validate_number(:add_on_seat_quantity, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:company_id)
  end
end
