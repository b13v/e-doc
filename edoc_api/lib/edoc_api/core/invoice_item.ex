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
    |> cast(attrs, @required ++ @optional)
    |> validate_required(@required)
    |> validate_number(:qty, greater_than: 0)
  end
end
