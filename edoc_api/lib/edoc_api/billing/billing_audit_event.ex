defmodule EdocApi.Billing.BillingAuditEvent do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "billing_audit_events" do
    field(:action, :string)
    field(:subject_type, :string)
    field(:subject_id, :binary_id)
    field(:metadata, :map, default: %{})

    belongs_to(:company, EdocApi.Core.Company)
    belongs_to(:actor_user, EdocApi.Accounts.User)

    timestamps(type: :utc_datetime)
  end

  def changeset(event, attrs) do
    event
    |> cast(attrs, [:company_id, :actor_user_id, :action, :subject_type, :subject_id, :metadata])
    |> validate_required([:company_id, :action, :subject_type])
    |> update_change(:action, &normalize_token/1)
    |> update_change(:subject_type, &normalize_token/1)
    |> validate_format(:action, ~r/^[a-z][a-z0-9_]*$/)
    |> validate_format(:subject_type, ~r/^[a-z][a-z0-9_]*$/)
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:actor_user_id)
  end

  defp normalize_token(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_token(value), do: value
end
