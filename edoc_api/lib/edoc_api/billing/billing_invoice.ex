defmodule EdocApi.Billing.BillingInvoice do
  use Ecto.Schema
  import Ecto.Changeset

  alias EdocApi.Billing.{BillingInvoiceStatus, Subscription}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @payment_methods ~w(kaspi_link manual bank_transfer)

  schema "billing_invoices" do
    field(:period_start, :utc_datetime)
    field(:period_end, :utc_datetime)
    field(:plan_snapshot_code, :string)
    field(:amount_kzt, :integer)
    field(:status, :string, default: BillingInvoiceStatus.draft())
    field(:payment_method, :string)
    field(:kaspi_payment_link, :string)
    field(:issued_at, :utc_datetime)
    field(:due_at, :utc_datetime)
    field(:paid_at, :utc_datetime)
    field(:note, :string)

    belongs_to(:company, EdocApi.Core.Company)
    belongs_to(:subscription, Subscription)
    belongs_to(:activated_by_user, EdocApi.Accounts.User)

    has_many(:payments, EdocApi.Billing.Payment)

    timestamps(type: :utc_datetime)
  end

  def changeset(invoice, attrs) do
    invoice
    |> cast(attrs, [
      :company_id,
      :subscription_id,
      :period_start,
      :period_end,
      :plan_snapshot_code,
      :amount_kzt,
      :status,
      :payment_method,
      :kaspi_payment_link,
      :issued_at,
      :due_at,
      :paid_at,
      :activated_by_user_id,
      :note
    ])
    |> update_change(:plan_snapshot_code, &normalize_code/1)
    |> validate_required([
      :company_id,
      :subscription_id,
      :period_start,
      :period_end,
      :plan_snapshot_code,
      :amount_kzt,
      :status
    ])
    |> validate_inclusion(:status, BillingInvoiceStatus.all())
    |> validate_optional_payment_method()
    |> validate_number(:amount_kzt, greater_than_or_equal_to: 0)
    |> validate_period(:period_start, :period_end)
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:subscription_id)
    |> foreign_key_constraint(:activated_by_user_id)
  end

  defp validate_optional_payment_method(changeset) do
    case get_field(changeset, :payment_method) do
      nil -> changeset
      _method -> validate_inclusion(changeset, :payment_method, @payment_methods)
    end
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

  defp normalize_code(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.downcase()
  end

  defp normalize_code(value), do: value
end
