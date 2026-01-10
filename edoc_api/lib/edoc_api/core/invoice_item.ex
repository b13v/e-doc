defmodule EdocApi.Core.InvoiceItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "invoice_items" do
    field(:code, :string)
    field(:name, :string)
    field(:qty, :integer, default: 1)
    field(:unit_price, :decimal)
    field(:amount, :decimal)

    belongs_to(:invoice, EdocApi.Core.Invoice)

    timestamps(type: :utc_datetime)
  end

  @required ~w(name qty unit_price amount)a
  @optional ~w(code)a

  def changeset(item, attrs) do
    item
    |> cast(attrs, @required ++ @optional ++ [:invoice_id])
    |> compute_amount()
    |> validate_required(@required ++ [:invoice_id])
    |> validate_number(:qty, greater_than: 0)
    |> validate_number(:unit_price, greater_than: 0)
  end

  defp compute_amount(changeset) do
    qty = get_field(changeset, :qty)
    unit_price = get_field(changeset, :unit_price)

    if is_integer(qty) and is_struct(unit_price, Decimal) do
      amount =
        unit_price
        |> Decimal.mult(Decimal.new(qty))
        |> Decimal.round(2)

      put_change(changeset, :amount, amount)
    else
      changeset
    end
  end
end
