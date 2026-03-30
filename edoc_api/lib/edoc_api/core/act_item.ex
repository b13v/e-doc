defmodule EdocApi.Core.ActItem do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "act_items" do
    field(:name, :string)
    field(:report_info, :string)
    field(:code, :string)
    field(:qty, :decimal)
    field(:unit_price, :decimal)
    field(:amount, :decimal)
    field(:vat_amount, :decimal)
    field(:actual_date, :date)

    belongs_to(:act, EdocApi.Core.Act)

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(
    act_id
    name
    code
    qty
    unit_price
    amount
    vat_amount
  )a
  @optional_fields ~w(report_info actual_date)a

  def changeset(item, attrs) do
    item
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_number(:qty, greater_than: 0)
    |> validate_number(:unit_price, greater_than: 0)
    |> validate_number(:amount, greater_than: 0)
    |> validate_number(:vat_amount, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:act_id)
  end
end
