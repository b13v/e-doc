defmodule EdocApi.Billing.Payment do
  use Ecto.Schema
  import Ecto.Changeset

  alias EdocApi.Billing.{BillingInvoice, PaymentStatus}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  @methods ~w(kaspi_link manual bank_transfer)

  schema "payments" do
    field(:amount_kzt, :integer)
    field(:method, :string)
    field(:status, :string, default: PaymentStatus.pending_confirmation())
    field(:paid_at, :utc_datetime)
    field(:confirmed_at, :utc_datetime)
    field(:external_reference, :string)
    field(:proof_attachment_url, :string)

    belongs_to(:company, EdocApi.Core.Company)
    belongs_to(:billing_invoice, BillingInvoice)
    belongs_to(:confirmed_by_user, EdocApi.Accounts.User)

    timestamps(type: :utc_datetime)
  end

  def changeset(payment, attrs) do
    payment
    |> cast(attrs, [
      :company_id,
      :billing_invoice_id,
      :amount_kzt,
      :method,
      :status,
      :paid_at,
      :confirmed_at,
      :confirmed_by_user_id,
      :external_reference,
      :proof_attachment_url
    ])
    |> validate_required([:company_id, :billing_invoice_id, :amount_kzt, :method, :status])
    |> validate_inclusion(:method, @methods)
    |> validate_inclusion(:status, PaymentStatus.all())
    |> validate_number(:amount_kzt, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:company_id)
    |> foreign_key_constraint(:billing_invoice_id)
    |> foreign_key_constraint(:confirmed_by_user_id)
  end
end
